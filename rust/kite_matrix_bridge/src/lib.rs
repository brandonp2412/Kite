use std::collections::{HashMap, HashSet};
use std::ffi::{CStr, CString, c_char};
use std::path::{Path, PathBuf};
use std::ptr;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64_STANDARD};
use matrix_sdk::{
    Client, Error as MatrixError, HttpError, RoomMemberships,
    authentication::matrix::MatrixSession,
    config::SyncSettings,
    encryption::{
        BackupDownloadStrategy, EncryptionSettings, backups::BackupState, recovery::RecoveryState,
    },
    media::{MediaFormat, MediaRequestParameters, MediaThumbnailSettings},
    notification_settings::RoomNotificationMode,
    room::MessagesOptions,
    ruma::{
        EventId, Int, OwnedDeviceId, OwnedEventId, OwnedMxcUri, OwnedTransactionId, OwnedUserId,
        RoomAliasId, RoomId, UInt, UserId,
        api::{
            client::{
                backup::{get_backup_keys, get_latest_backup_info},
                filter::{FilterDefinition, RoomEventFilter, RoomFilter},
                profile::{AvatarUrl, DisplayName},
                receipt::create_receipt,
                reporting::report_user,
                room::{Visibility, create_room},
                session::get_login_types::v3::LoginType,
                uiaa,
            },
            error::ErrorKind,
        },
        events::{
            InitialStateEvent,
            ignored_user_list::IgnoredUserListEventContent,
            receipt::ReceiptThread,
            relation::Reply,
            room::{
                MediaSource,
                encryption::RoomEncryptionEventContent,
                history_visibility::{HistoryVisibility, RoomHistoryVisibilityEventContent},
                join_rules::{JoinRule, RoomJoinRulesEventContent},
                message::{Relation, ReplacementMetadata, RoomMessageEventContent},
                power_levels::UserPowerLevel,
            },
        },
    },
};
use matrix_sdk_crypto::{
    encrypt_room_key_export, olm::ExportedRoomKey, store::types::BackupDecryptionKey,
    types::RoomKeyBackupInfo,
};
use serde::Deserialize;
use serde_json::{Value, json};
use tokio::{
    runtime::{Builder, Runtime},
    task::JoinSet,
};

const KITE_MATRIX_ABI_VERSION: u32 = 27;
const KITE_MATRIX_SESSION_STORE_KEY: &[u8] = b"kite.matrix.session.v1";
const KITE_MATRIX_MEDIA_PREFETCH_CONCURRENCY: usize = 6;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct CreateRoomRequest {
    kind: String,
    name: Option<String>,
    topic: Option<String>,
    invitees: Vec<String>,
    join_rule: String,
    encryption_enabled: bool,
    history_visibility: String,
    canonical_alias: Option<String>,
    parent_space_id: Option<String>,
}

pub struct KiteMatrixClient {
    client: Option<Client>,
    runtime: Runtime,
    backwards_pagination_tokens: HashMap<String, String>,
    room_metadata_hydrated: bool,
}

#[unsafe(no_mangle)]
pub extern "C" fn kite_matrix_abi_version() -> u32 {
    KITE_MATRIX_ABI_VERSION
}

unsafe fn required_utf8<'a>(value: *const c_char) -> Option<&'a str> {
    if value.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(value) }.to_str().ok()
}

fn json_to_c_string(value: &Value) -> *mut c_char {
    let Ok(serialized) = serde_json::to_string(value) else {
        return ptr::null_mut();
    };
    let Ok(serialized) = CString::new(serialized) else {
        return ptr::null_mut();
    };
    serialized.into_raw()
}

fn ok_json(value: Value) -> *mut c_char {
    json_to_c_string(&json!({"ok": true, "value": value}))
}

fn error_json(code: &str, public_message: &str) -> *mut c_char {
    json_to_c_string(&json!({
        "ok": false,
        "error": {"code": code, "message": public_message},
    }))
}

fn session_json(session: &MatrixSession, homeserver: &str) -> Value {
    json!({
        "userId": session.meta.user_id.as_str(),
        "deviceId": session.meta.device_id.as_str(),
        "homeserver": homeserver,
    })
}

fn persist_session_if_access_token_changed(
    runtime: &Runtime,
    client: &Client,
    previous_access_token: Option<&str>,
) -> Result<(), ()> {
    let Some(session) = client.matrix_auth().session() else {
        return Err(());
    };
    if previous_access_token == Some(session.tokens.access_token.as_str()) {
        return Ok(());
    }
    let session_bytes = serde_json::to_vec(&session).map_err(|_| ())?;
    runtime
        .block_on(
            client
                .state_store()
                .set_custom_value(KITE_MATRIX_SESSION_STORE_KEY, session_bytes),
        )
        .map(|_| ())
        .map_err(|_| ())
}

fn replace_backwards_pagination_tokens<'a>(
    tokens: &mut HashMap<String, String>,
    room_prev_batches: impl IntoIterator<Item = (&'a str, Option<&'a str>)>,
) {
    tokens.clear();
    for (room_id, prev_batch) in room_prev_batches {
        if let Some(prev_batch) = prev_batch.filter(|value| !value.is_empty()) {
            tokens.insert(room_id.to_owned(), prev_batch.to_owned());
        }
    }
}

fn timeline_events_json<'a>(
    runtime: &Runtime,
    room: Option<&matrix_sdk::Room>,
    events: impl IntoIterator<Item = &'a matrix_sdk::deserialized_responses::TimelineEvent>,
) -> Vec<Value> {
    let mut events = events
        .into_iter()
        .filter_map(|event| serde_json::from_str(event.raw().json().get()).ok())
        .collect::<Vec<Value>>();
    let Some(room) = room else {
        return events;
    };
    let senders = events
        .iter()
        .filter_map(|event| event.get("sender").and_then(Value::as_str))
        .map(str::to_owned)
        .collect::<HashSet<_>>();
    let (display_names, avatar_urls) = runtime.block_on(async {
        let mut display_names = HashMap::new();
        let mut avatar_urls = HashMap::new();
        for sender in senders {
            let Ok(user_id) = UserId::parse(sender.as_str()) else {
                continue;
            };
            let member = room.get_member_no_sync(&user_id).await.ok().flatten();
            let display_name = member
                .as_ref()
                .and_then(|member| member.display_name().map(str::to_owned))
                .filter(|display_name| !display_name.trim().is_empty());
            let avatar_url = member
                .as_ref()
                .and_then(|member| member.avatar_url().map(|url| url.to_string()));
            if let Some(display_name) = display_name {
                display_names.insert(sender.clone(), display_name);
            }
            if let Some(avatar_url) = avatar_url {
                avatar_urls.insert(sender, avatar_url);
            }
        }
        (display_names, avatar_urls)
    });
    for event in &mut events {
        let Some(sender) = event
            .get("sender")
            .and_then(Value::as_str)
            .map(str::to_owned)
        else {
            continue;
        };
        if let Some(event) = event.as_object_mut() {
            if let Some(display_name) = display_names.get(&sender) {
                event.insert(
                    "sender_display_name".to_owned(),
                    Value::String(display_name.clone()),
                );
            }
            if let Some(avatar_url) = avatar_urls.get(&sender) {
                event.insert(
                    "sender_avatar_url".to_owned(),
                    Value::String(avatar_url.clone()),
                );
            }
        }
    }
    events
}

fn sync_error_json(error: &MatrixError) -> *mut c_char {
    let code = match error.client_api_error_kind() {
        Some(ErrorKind::UnknownPos) => "unknown_pos",
        Some(ErrorKind::UnknownToken(_)) => "unknown_token",
        _ => match error {
            MatrixError::Http(http) => match http.as_ref() {
                HttpError::Reqwest(_) => "network_failed",
                HttpError::RefreshToken(_) => "refresh_token_failed",
                HttpError::Api(_) => "api_failed",
                _ => "http_failed",
            },
            MatrixError::AuthenticationRequired => "authentication_required",
            MatrixError::StateStore(_) => "state_store_failed",
            MatrixError::EventCacheStore(_) => "event_cache_store_failed",
            _ => "sync_failed",
        },
    };
    json_to_c_string(&json!({"error": {"code": code}}))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_new(
    homeserver: *const c_char,
    store_path: *const c_char,
    store_passphrase: *const c_char,
) -> *mut KiteMatrixClient {
    let Some(homeserver) = (unsafe { required_utf8(homeserver) }) else {
        return ptr::null_mut();
    };
    let Some(store_path) = (unsafe { required_utf8(store_path) }) else {
        return ptr::null_mut();
    };
    let Some(store_passphrase) = (unsafe { required_utf8(store_passphrase) }) else {
        return ptr::null_mut();
    };
    if store_path.is_empty() || store_passphrase.is_empty() {
        return ptr::null_mut();
    }

    let Ok(runtime) = Builder::new_multi_thread().enable_all().build() else {
        return ptr::null_mut();
    };
    let builder = Client::builder()
        .homeserver_url(homeserver)
        .handle_refresh_tokens()
        .with_encryption_settings(EncryptionSettings {
            backup_download_strategy: BackupDownloadStrategy::OneShot,
            ..Default::default()
        })
        .sqlite_store(Path::new(store_path), Some(store_passphrase));
    let Ok(client) = runtime.block_on(builder.build()) else {
        return ptr::null_mut();
    };
    let session_bytes = match runtime.block_on(
        client
            .state_store()
            .get_custom_value(KITE_MATRIX_SESSION_STORE_KEY),
    ) {
        Ok(value) => value,
        Err(_) => return ptr::null_mut(),
    };
    if let Some(session_bytes) = session_bytes {
        let Ok(session) = serde_json::from_slice::<MatrixSession>(&session_bytes) else {
            return ptr::null_mut();
        };
        if runtime.block_on(client.restore_session(session)).is_err() {
            return ptr::null_mut();
        }
    }
    if runtime
        .block_on(async { client.event_cache().subscribe() })
        .is_err()
    {
        return ptr::null_mut();
    }

    Box::into_raw(Box::new(KiteMatrixClient {
        client: Some(client),
        runtime,
        backwards_pagination_tokens: HashMap::new(),
        room_metadata_hydrated: false,
    }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_discover_authentication(
    homeserver: *const c_char,
) -> *mut c_char {
    let Some(homeserver) = (unsafe { required_utf8(homeserver) }) else {
        return error_json("invalid_homeserver", "Enter a valid Matrix homeserver.");
    };
    if homeserver.trim().is_empty() {
        return error_json("invalid_homeserver", "Enter a valid Matrix homeserver.");
    }

    let Ok(runtime) = Builder::new_current_thread().enable_all().build() else {
        return error_json(
            "native_runtime_failed",
            "Matrix authentication is unavailable.",
        );
    };
    let result = runtime.block_on(async {
        let client = Client::builder()
            .homeserver_url(homeserver)
            .build()
            .await
            .map_err(|_| ())?;
        let flows = client
            .matrix_auth()
            .get_login_types()
            .await
            .map_err(|_| ())?;
        let password = flows
            .flows
            .iter()
            .any(|flow| matches!(flow, LoginType::Password(_)));
        Ok::<Value, ()>(json!({
            "homeserver": client.homeserver().as_str(),
            "password": password,
        }))
    });

    match result {
        Ok(value) => ok_json(value),
        Err(()) => error_json(
            "discovery_failed",
            "Could not discover this Matrix homeserver.",
        ),
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_login_password(
    client: *mut KiteMatrixClient,
    username: *const c_char,
    password: *const c_char,
) -> *mut c_char {
    if client.is_null() {
        return error_json("client_closed", "Matrix authentication is unavailable.");
    }
    let Some(username) = (unsafe { required_utf8(username) }) else {
        return error_json(
            "invalid_credentials",
            "Enter a Matrix username and password.",
        );
    };
    let Some(password) = (unsafe { required_utf8(password) }) else {
        return error_json(
            "invalid_credentials",
            "Enter a Matrix username and password.",
        );
    };
    if username.trim().is_empty() || password.is_empty() {
        return error_json(
            "invalid_credentials",
            "Enter a Matrix username and password.",
        );
    }

    let client = unsafe { &mut *client };
    let Some(matrix_client) = client.client.as_ref() else {
        return error_json("client_closed", "Matrix authentication is unavailable.");
    };
    let existing_device_id = matrix_client
        .matrix_auth()
        .session()
        .map(|session| session.meta.device_id);
    let mut login = matrix_client
        .matrix_auth()
        .login_username(username, password)
        .initial_device_display_name("Kite")
        .request_refresh_token();
    if let Some(device_id) = existing_device_id.as_deref() {
        login = login.device_id(device_id.as_str());
    }
    let Ok(response) = client.runtime.block_on(login.send()) else {
        return error_json("authentication_rejected", "Matrix login was rejected.");
    };
    let session = MatrixSession::from(&response);
    let Ok(session_bytes) = serde_json::to_vec(&session) else {
        return error_json(
            "session_persist_failed",
            "Could not save the Matrix session.",
        );
    };
    if client
        .runtime
        .block_on(
            matrix_client
                .state_store()
                .set_custom_value(KITE_MATRIX_SESSION_STORE_KEY, session_bytes),
        )
        .is_err()
    {
        return error_json(
            "session_persist_failed",
            "Could not save the Matrix session.",
        );
    }

    client.room_metadata_hydrated = false;
    ok_json(session_json(&session, matrix_client.homeserver().as_str()))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_logout(client: *mut KiteMatrixClient) -> *mut c_char {
    if client.is_null() {
        return error_json("client_closed", "Matrix sign-out is unavailable.");
    }
    let client = unsafe { &mut *client };
    let Some(matrix_client) = client.client.as_ref() else {
        return error_json("client_closed", "Matrix sign-out is unavailable.");
    };
    if matrix_client.matrix_auth().session().is_none() {
        return error_json(
            "session_unavailable",
            "There is no Matrix session to sign out.",
        );
    }
    if client.runtime.block_on(matrix_client.logout()).is_err() {
        return error_json(
            "logout_failed",
            "Could not sign out from the Matrix server.",
        );
    }
    client.room_metadata_hydrated = false;
    ok_json(Value::Null)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_persist_session(
    client: *mut KiteMatrixClient,
) -> *mut c_char {
    if client.is_null() {
        return error_json(
            "client_closed",
            "Matrix session persistence is unavailable.",
        );
    }
    let client = unsafe { &mut *client };
    let Some(matrix_client) = client.client.as_ref() else {
        return error_json(
            "client_closed",
            "Matrix session persistence is unavailable.",
        );
    };
    let Some(session) = matrix_client.matrix_auth().session() else {
        return error_json("session_unavailable", "There is no Matrix session to save.");
    };
    let Ok(session_bytes) = serde_json::to_vec(&session) else {
        return error_json(
            "session_persist_failed",
            "Could not save the Matrix session.",
        );
    };
    if client
        .runtime
        .block_on(
            matrix_client
                .state_store()
                .set_custom_value(KITE_MATRIX_SESSION_STORE_KEY, session_bytes),
        )
        .is_err()
    {
        return error_json(
            "session_persist_failed",
            "Could not save the Matrix session.",
        );
    }
    ok_json(Value::Null)
}

fn recovery_status_value(matrix_client: &Client) -> Value {
    let recovery_state = matrix_client.encryption().recovery().state();
    let recovery_state_name = match recovery_state {
        RecoveryState::Unknown => "unknown",
        RecoveryState::Enabled => "enabled",
        RecoveryState::Disabled => "disabled",
        RecoveryState::Incomplete => "incomplete",
    };
    let backup_state_value = matrix_client.encryption().backups().state();
    let backup_exists_on_server = matches!(
        recovery_state,
        RecoveryState::Enabled | RecoveryState::Incomplete
    ) || !matches!(backup_state_value, BackupState::Unknown);
    let backup_state = match backup_state_value {
        BackupState::Unknown => "unknown",
        BackupState::Creating => "creating",
        BackupState::Enabling => "enabling",
        BackupState::Resuming => "resuming",
        BackupState::Enabled => "enabled",
        BackupState::Downloading => "downloading",
        BackupState::Disabling => "disabling",
    };
    json!({
        "recoveryState": recovery_state_name,
        "backupState": backup_state,
        "backupExistsOnServer": backup_exists_on_server,
    })
}

fn recovery_status_value_with_server_probe(runtime: &Runtime, matrix_client: &Client) -> Value {
    let mut status = recovery_status_value(matrix_client);
    if status["backupExistsOnServer"].as_bool() == Some(false) {
        let backup_exists = runtime.block_on(async {
            matches!(
                tokio::time::timeout(
                    Duration::from_secs(12),
                    matrix_client.send(get_latest_backup_info::v3::Request::new()),
                )
                .await,
                Ok(Ok(_))
            )
        });
        if backup_exists {
            status["backupExistsOnServer"] = Value::Bool(true);
        }
    }
    status
}

async fn download_recoverable_room_keys(matrix_client: &Client) -> Result<(), MatrixError> {
    for room in matrix_client.rooms() {
        matrix_client
            .encryption()
            .backups()
            .download_room_keys_for_room(room.room_id())
            .await?;
    }
    Ok(())
}

async fn recover_with_backup_recovery_key(
    matrix_client: &Client,
    recovery_key: &str,
) -> Result<(), ()> {
    let decryption_key = BackupDecryptionKey::from_base58(recovery_key).map_err(|_| ())?;
    let current_version = matrix_client
        .send(get_latest_backup_info::v3::Request::new())
        .await
        .map_err(|_| ())?;
    let backup_info: RoomKeyBackupInfo =
        current_version.algorithm.deserialize_as().map_err(|_| ())?;
    if !decryption_key.backup_key_matches(&backup_info) {
        return Err(());
    }

    let response = matrix_client
        .send(get_backup_keys::v3::Request::new(current_version.version))
        .await
        .map_err(|_| ())?;
    let mut exported_room_keys = Vec::new();

    for (room_id, room_keys) in response.rooms {
        for (session_id, room_key) in room_keys.sessions {
            let room_key = room_key.deserialize().map_err(|_| ())?;
            let backed_up_room_key = decryption_key
                .decrypt_session_data(room_key.session_data)
                .map_err(|_| ())?;
            exported_room_keys.push(ExportedRoomKey::from_backed_up_room_key(
                room_id.to_owned(),
                session_id,
                backed_up_room_key,
            ));
        }
    }

    if exported_room_keys.is_empty() {
        return Ok(());
    }

    // The Matrix SDK only exposes raw room-key imports through its internal
    // OlmMachine. Keep production builds off the SDK's `testing` feature by
    // round-tripping the already-decrypted keys through its public encrypted
    // key-export importer. The file lives only in the app-private temp dir and
    // is removed immediately after import.
    let encrypted_export =
        encrypt_room_key_export(&exported_room_keys, recovery_key, 100_000).map_err(|_| ())?;
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let import_path = std::env::temp_dir().join(format!(
        "kite-matrix-room-key-import-{}-{nonce}.txt",
        std::process::id()
    ));
    std::fs::write(&import_path, encrypted_export).map_err(|_| ())?;
    let import_result = matrix_client
        .encryption()
        .import_room_keys(import_path.clone(), recovery_key)
        .await;
    let _ = std::fs::remove_file(import_path);

    import_result.map(|_| ()).map_err(|_| ())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_recovery(
    client: *mut KiteMatrixClient,
    action: *const c_char,
    secret: *const c_char,
) -> *mut c_char {
    if client.is_null() {
        return error_json(
            "client_closed",
            "Matrix encryption recovery is unavailable.",
        );
    }
    let Some(action) = (unsafe { required_utf8(action) }) else {
        return error_json(
            "invalid_recovery_action",
            "Matrix encryption recovery is unavailable.",
        );
    };
    let client = unsafe { &mut *client };
    let Some(matrix_client) = client.client.as_ref() else {
        return error_json(
            "client_closed",
            "Matrix encryption recovery is unavailable.",
        );
    };
    if matrix_client.matrix_auth().session().is_none() {
        return error_json(
            "session_unavailable",
            "Matrix encryption recovery requires an authenticated session.",
        );
    }

    match action {
        "status" => ok_json(recovery_status_value_with_server_probe(
            &client.runtime,
            matrix_client,
        )),
        "create_backup" => {
            if client
                .runtime
                .block_on(matrix_client.encryption().recovery().enable_backup())
                .is_err()
            {
                return error_json(
                    "backup_creation_failed",
                    "Matrix could not enable encrypted backup.",
                );
            }
            ok_json(recovery_status_value(matrix_client))
        }
        "recover" => {
            let Some(secret) = (unsafe { required_utf8(secret) }) else {
                return error_json(
                    "recovery_secret_required",
                    "A Matrix recovery key or passphrase is required.",
                );
            };
            if secret.is_empty() {
                return error_json(
                    "recovery_secret_required",
                    "A Matrix recovery key or passphrase is required.",
                );
            }
            let result = client.runtime.block_on(async {
                if matrix_client
                    .encryption()
                    .recovery()
                    .recover(secret)
                    .await
                    .is_ok()
                {
                    download_recoverable_room_keys(matrix_client)
                        .await
                        .map_err(|_| ())?;
                    return Ok(false);
                }

                recover_with_backup_recovery_key(matrix_client, secret).await?;
                Ok(true)
            });
            let recovered_from_backup_key = match result {
                Ok(recovered_from_backup_key) => recovered_from_backup_key,
                Err(()) => {
                    return error_json(
                        "recovery_failed",
                        "Matrix could not restore encrypted message history with that recovery key.",
                    );
                }
            };
            if recovered_from_backup_key {
                let mut status = recovery_status_value(matrix_client);
                status["backupState"] = Value::String("enabled".to_owned());
                status["backupExistsOnServer"] = Value::Bool(true);
                ok_json(status)
            } else {
                ok_json(recovery_status_value(matrix_client))
            }
        }
        "recover_history" => {
            if client
                .runtime
                .block_on(download_recoverable_room_keys(matrix_client))
                .is_err()
            {
                return error_json(
                    "history_recovery_failed",
                    "Matrix could not recover encrypted message history.",
                );
            }
            ok_json(recovery_status_value(matrix_client))
        }
        _ => error_json(
            "invalid_recovery_action",
            "Matrix encryption recovery is unavailable.",
        ),
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_import_room_keys(
    client: *mut KiteMatrixClient,
    path: *const c_char,
    passphrase: *const c_char,
) -> *mut c_char {
    if client.is_null() {
        return error_json("client_closed", "Matrix room-key import is unavailable.");
    }
    let Some(path) = (unsafe { required_utf8(path) }) else {
        return error_json(
            "room_key_import_path_required",
            "Choose a Matrix room-key backup file.",
        );
    };
    let Some(passphrase) = (unsafe { required_utf8(passphrase) }) else {
        return error_json(
            "room_key_import_passphrase_required",
            "Enter the room-key backup passphrase.",
        );
    };
    if path.is_empty() || passphrase.is_empty() {
        return error_json(
            "room_key_import_invalid_input",
            "Choose a room-key backup and enter its passphrase.",
        );
    }

    let client = unsafe { &mut *client };
    let Some(matrix_client) = client.client.as_ref() else {
        return error_json("client_closed", "Matrix room-key import is unavailable.");
    };
    if matrix_client.matrix_auth().session().is_none() {
        return error_json(
            "session_unavailable",
            "Matrix room-key import requires an authenticated session.",
        );
    }

    let result = client.runtime.block_on(
        matrix_client
            .encryption()
            .import_room_keys(PathBuf::from(path), passphrase),
    );
    match result {
        Ok(imported) => ok_json(json!({
            "importedCount": imported.imported_count,
            "totalCount": imported.total_count,
        })),
        Err(_) => error_json(
            "room_key_import_failed",
            "The room-key backup could not be decrypted. Check its export passphrase.",
        ),
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_restore_session(
    client: *mut KiteMatrixClient,
) -> *mut c_char {
    if client.is_null() {
        return error_json("client_closed", "Matrix session restore is unavailable.");
    }
    let client = unsafe { &mut *client };
    let Some(matrix_client) = client.client.as_ref() else {
        return error_json("client_closed", "Matrix session restore is unavailable.");
    };
    if let Some(session) = matrix_client.matrix_auth().session() {
        return ok_json(session_json(&session, matrix_client.homeserver().as_str()));
    }
    let stored = match client.runtime.block_on(
        matrix_client
            .state_store()
            .get_custom_value(KITE_MATRIX_SESSION_STORE_KEY),
    ) {
        Ok(value) => value,
        Err(_) => {
            return error_json(
                "session_restore_failed",
                "Could not restore the Matrix session.",
            );
        }
    };
    let Some(stored) = stored else {
        return ok_json(Value::Null);
    };
    let Ok(session) = serde_json::from_slice::<MatrixSession>(&stored) else {
        return error_json(
            "session_restore_failed",
            "Could not restore the Matrix session.",
        );
    };
    if client
        .runtime
        .block_on(matrix_client.restore_session(session.clone()))
        .is_err()
    {
        return error_json(
            "session_restore_failed",
            "Could not restore the Matrix session.",
        );
    }
    client.room_metadata_hydrated = false;
    ok_json(session_json(&session, matrix_client.homeserver().as_str()))
}

fn text_message_content(
    body: &str,
    reply_to_event_id: Option<OwnedEventId>,
    replacement_event_id: Option<OwnedEventId>,
) -> RoomMessageEventContent {
    let mut content = RoomMessageEventContent::text_plain(body);
    if let Some(event_id) = replacement_event_id {
        return content.make_replacement(ReplacementMetadata::new(event_id, None));
    }
    if let Some(event_id) = reply_to_event_id {
        content.relates_to = Some(Relation::Reply(Reply::with_event_id(event_id)));
    }
    content
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_send_text(
    client: *mut KiteMatrixClient,
    room_id: *const c_char,
    transaction_id: *const c_char,
    body: *const c_char,
    reply_to_event_id: *const c_char,
    replacement_event_id: *const c_char,
) -> *mut c_char {
    if client.is_null() {
        return error_json("client_closed", "Matrix message sending is unavailable.");
    }
    let Some(room_id) = (unsafe { required_utf8(room_id) }) else {
        return error_json("invalid_room", "The Matrix room is invalid.");
    };
    let Some(transaction_id) = (unsafe { required_utf8(transaction_id) }) else {
        return error_json(
            "invalid_transaction",
            "The Matrix transaction ID is invalid.",
        );
    };
    let Some(body) = (unsafe { required_utf8(body) }) else {
        return error_json("invalid_message", "The Matrix message is invalid.");
    };
    let reply_to_event_id = unsafe { required_utf8(reply_to_event_id) };
    let replacement_event_id = unsafe { required_utf8(replacement_event_id) };
    if room_id.is_empty() || transaction_id.is_empty() || body.is_empty() {
        return error_json("invalid_message", "The Matrix message is invalid.");
    }
    let Ok(room_id) = RoomId::parse(room_id) else {
        return error_json("invalid_room", "The Matrix room is invalid.");
    };
    let reply_to_event_id = match reply_to_event_id {
        Some(event_id) => match EventId::parse(event_id) {
            Ok(event_id) => Some(event_id),
            Err(_) => {
                return error_json("invalid_reply", "The Matrix reply target is invalid.");
            }
        },
        None => None,
    };
    let replacement_event_id = match replacement_event_id {
        Some(event_id) => match EventId::parse(event_id) {
            Ok(event_id) => Some(event_id),
            Err(_) => {
                return error_json(
                    "invalid_replacement",
                    "The Matrix replacement target is invalid.",
                );
            }
        },
        None => None,
    };
    if reply_to_event_id.is_some() && replacement_event_id.is_some() {
        return error_json(
            "invalid_relation",
            "A Matrix text event cannot be both a reply and a replacement.",
        );
    }

    let client = unsafe { &mut *client };
    let Some(matrix_client) = client.client.as_ref() else {
        return error_json("client_closed", "Matrix message sending is unavailable.");
    };
    let Some(room) = matrix_client.get_room(&room_id) else {
        return error_json("room_unavailable", "This Matrix room is not available yet.");
    };
    if !room.are_members_synced() && client.runtime.block_on(room.sync_members()).is_err() {
        return error_json("send_failed", "The Matrix message could not be sent.");
    }
    let previous_access_token = matrix_client
        .matrix_auth()
        .session()
        .map(|session| session.tokens.access_token);
    let content = text_message_content(body, reply_to_event_id, replacement_event_id);
    let Ok(response) = client.runtime.block_on(async {
        room.send(content)
            .with_transaction_id(OwnedTransactionId::from(transaction_id))
            .await
    }) else {
        return error_json("send_failed", "The Matrix message could not be sent.");
    };
    if persist_session_if_access_token_changed(
        &client.runtime,
        matrix_client,
        previous_access_token.as_deref(),
    )
    .is_err()
    {
        return error_json(
            "session_persist_failed",
            "Could not save the refreshed Matrix session.",
        );
    }

    ok_json(json!({"eventId": response.response.event_id.as_str()}))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_sync_once(
    client: *mut KiteMatrixClient,
    timeout_ms: u64,
    since: *const c_char,
    timeline_event_limit: u64,
) -> *mut c_char {
    if client.is_null() {
        return ptr::null_mut();
    }
    let client = unsafe { &mut *client };
    let Some(matrix_client) = client.client.as_ref() else {
        return ptr::null_mut();
    };

    let Some(timeline_event_limit) = UInt::new(timeline_event_limit) else {
        return ptr::null_mut();
    };
    if timeline_event_limit == UInt::from(0_u8) {
        return ptr::null_mut();
    }
    let mut timeline_filter = RoomEventFilter::default();
    timeline_filter.limit = Some(timeline_event_limit);
    let mut room_filter = RoomFilter::with_lazy_loading();
    room_filter.timeline = timeline_filter;
    let mut filter = FilterDefinition::default();
    filter.room = room_filter;
    let mut settings = SyncSettings::default()
        .timeout(Duration::from_millis(timeout_ms))
        .filter(filter.into());
    let replace_invites = since.is_null();
    if !since.is_null() {
        let Some(since) = (unsafe { required_utf8(since) }) else {
            return ptr::null_mut();
        };
        if since.is_empty() {
            return ptr::null_mut();
        }
        settings = settings.token(since);
    }
    let previous_access_token = matrix_client
        .matrix_auth()
        .session()
        .map(|session| session.tokens.access_token);
    let response = match client.runtime.block_on(matrix_client.sync_once(settings)) {
        Ok(response) => response,
        Err(error) => return sync_error_json(&error),
    };
    if persist_session_if_access_token_changed(
        &client.runtime,
        matrix_client,
        previous_access_token.as_deref(),
    )
    .is_err()
    {
        return json_to_c_string(&json!({
            "error": {"code": "session_persist_failed"},
        }));
    }

    if replace_invites {
        replace_backwards_pagination_tokens(
            &mut client.backwards_pagination_tokens,
            response
                .rooms
                .joined
                .iter()
                .map(|(room_id, update)| (room_id.as_str(), update.timeline.prev_batch.as_deref())),
        );
    }

    let hydrate_room_metadata = !client.room_metadata_hydrated;
    let metadata_room_ids = if hydrate_room_metadata {
        matrix_client
            .joined_rooms()
            .into_iter()
            .map(|room| room.room_id().to_owned())
            .collect::<Vec<_>>()
    } else {
        response.rooms.joined.keys().cloned().collect::<Vec<_>>()
    };
    let (muted_room_ids, direct_room_ids) = client.runtime.block_on(async {
        let settings = matrix_client.notification_settings().await;
        let mut muted = HashSet::new();
        let mut direct = HashSet::new();
        for room_id in metadata_room_ids {
            if settings
                .get_user_defined_room_notification_mode(&room_id)
                .await
                == Some(RoomNotificationMode::Mute)
            {
                muted.insert(room_id.clone());
            }
            if let Some(room) = matrix_client.get_room(&room_id) {
                if room.is_direct().await.unwrap_or(false) {
                    direct.insert(room_id);
                }
            }
        }
        (muted, direct)
    });
    let invites = response
        .rooms
        .invited
        .keys()
        .filter_map(|room_id| {
            let room = matrix_client.get_room(room_id)?;
            let display_name = room
                .cached_display_name()
                .map(|name| name.to_string())
                .unwrap_or_else(|| room_id.as_str().to_owned());
            let invite = client.runtime.block_on(room.invite_details()).ok()?;
            let inviter_display_name = invite
                .inviter
                .as_ref()
                .and_then(|member| member.display_name())
                .filter(|name| !name.trim().is_empty())
                .unwrap_or(invite.inviter_id.as_str())
                .to_owned();
            Some(json!({
                "roomId": room_id.as_str(),
                "roomName": display_name,
                "inviterId": invite.inviter_id.as_str(),
                "inviterDisplayName": inviter_display_name,
                "memberCount": room.active_members_count(),
                "description": room.topic().filter(|topic| !topic.trim().is_empty()),
            }))
        })
        .collect::<Vec<_>>();
    let removed_invite_room_ids = response
        .rooms
        .joined
        .keys()
        .chain(response.rooms.left.keys())
        .map(|room_id| room_id.as_str())
        .collect::<Vec<_>>();
    let removed_room_ids = response
        .rooms
        .left
        .keys()
        .map(|room_id| room_id.as_str())
        .collect::<Vec<_>>();

    let mut rooms = response
        .rooms
        .joined
        .iter()
        .map(|(room_id, update)| {
            let room = matrix_client.get_room(room_id);
            let display_name = room
                .as_ref()
                .and_then(|room| room.cached_display_name())
                .map(|name| name.to_string())
                .unwrap_or_else(|| room_id.as_str().to_owned());
            let latest_event = room.as_ref().map(|room| room.latest_event());
            let latest_event_timestamp = latest_event
                .as_ref()
                .and_then(|event| event.timestamp())
                .map(|timestamp| Into::<u64>::into(timestamp.get()));
            let latest_event_id = latest_event
                .and_then(|event| event.event_id())
                .map(|event_id| event_id.to_string());
            let unread_count = update.unread_notifications.notification_count;
            let highlight_count = update.unread_notifications.highlight_count;
            let has_active_call = room
                .as_ref()
                .is_some_and(|room| room.has_active_room_call());
            let is_favourite = room.as_ref().is_some_and(|room| room.is_favourite());
            let is_muted = muted_room_ids.contains(room_id);
            let is_direct = direct_room_ids.contains(room_id);
            let avatar_url = room.as_ref().and_then(|room| {
                if let Some(avatar_url) = room.avatar_url() {
                    return Some(avatar_url.to_string());
                }
                if !is_direct {
                    return None;
                }
                let direct_user_ids = room
                    .direct_targets()
                    .into_iter()
                    .filter_map(|target| target.into_user_id())
                    .collect::<Vec<_>>();
                if direct_user_ids.len() != 1 {
                    return None;
                }
                client
                    .runtime
                    .block_on(room.get_member_no_sync(&direct_user_ids[0]))
                    .ok()
                    .flatten()
                    .and_then(|member| member.avatar_url().map(|url| url.to_string()))
            });
            json!({
                "roomId": room_id.as_str(),
                "displayName": display_name,
                "avatarUrl": avatar_url,
                "unreadCount": unread_count,
                "highlightCount": highlight_count,
                "hasActiveCall": has_active_call,
                "isFavourite": is_favourite,
                "isMuted": is_muted,
                "isDirect": is_direct,
                "latestEventTimestamp": latest_event_timestamp,
                "latestEventId": latest_event_id,
                "prevBatch": update.timeline.prev_batch,
                "events": timeline_events_json(
                    &client.runtime,
                    room.as_ref(),
                    update.timeline.events.iter(),
                ),
            })
        })
        .collect::<Vec<_>>();

    if hydrate_room_metadata {
        for room in matrix_client.joined_rooms() {
            let room_id = room.room_id();
            if response.rooms.joined.contains_key(room_id) {
                continue;
            }
            let display_name = room
                .cached_display_name()
                .map(|name| name.to_string())
                .unwrap_or_else(|| room_id.as_str().to_owned());
            let latest_event = room.latest_event();
            let latest_event_timestamp = latest_event
                .timestamp()
                .map(|timestamp| Into::<u64>::into(timestamp.get()));
            let latest_event_id = latest_event.event_id().map(|event_id| event_id.to_string());
            let unread_count = room.num_unread_messages();
            let highlight_count = room.num_unread_mentions();
            let has_active_call = room.has_active_room_call();
            let is_favourite = room.is_favourite();
            let is_muted = muted_room_ids.contains(room_id);
            let is_direct = direct_room_ids.contains(room_id);
            let avatar_url = if let Some(avatar_url) = room.avatar_url() {
                Some(avatar_url.to_string())
            } else if is_direct {
                let direct_user_ids = room
                    .direct_targets()
                    .into_iter()
                    .filter_map(|target| target.into_user_id())
                    .collect::<Vec<_>>();
                if direct_user_ids.len() == 1 {
                    client
                        .runtime
                        .block_on(room.get_member_no_sync(&direct_user_ids[0]))
                        .ok()
                        .flatten()
                        .and_then(|member| member.avatar_url().map(|url| url.to_string()))
                } else {
                    None
                }
            } else {
                None
            };
            rooms.push(json!({
                "roomId": room_id.as_str(),
                "displayName": display_name,
                "avatarUrl": avatar_url,
                "unreadCount": unread_count,
                "highlightCount": highlight_count,
                "hasActiveCall": has_active_call,
                "isFavourite": is_favourite,
                "isMuted": is_muted,
                "isDirect": is_direct,
                "latestEventTimestamp": latest_event_timestamp,
                "latestEventId": latest_event_id,
                "prevBatch": Value::Null,
                "events": [],
            }));
        }
        client.room_metadata_hydrated = true;
    }

    json_to_c_string(&json!({
        "cursor": response.next_batch,
        "rooms": rooms,
        "invites": invites,
        "removedInviteRoomIds": removed_invite_room_ids,
        "removedRoomIds": removed_room_ids,
        "replaceInvites": replace_invites,
    }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_create_room(
    client: *mut KiteMatrixClient,
    request_json: *const c_char,
) -> *mut c_char {
    if client.is_null() {
        return error_json("client_closed", "Matrix room creation is unavailable.");
    }
    let Some(request_json) = (unsafe { required_utf8(request_json) }) else {
        return error_json(
            "invalid_room_request",
            "The room creation request is invalid.",
        );
    };
    let Ok(request) = serde_json::from_str::<CreateRoomRequest>(request_json) else {
        return error_json(
            "invalid_room_request",
            "The room creation request is invalid.",
        );
    };
    if request.parent_space_id.is_some() {
        return error_json(
            "unsupported_parent_space",
            "Creating a room inside a Space is not available yet.",
        );
    }

    let is_direct = request.kind == "directMessage";
    let is_private = request.kind == "privateRoom";
    let is_public = request.kind == "publicRoom";
    if !is_direct && !is_private && !is_public {
        return error_json("invalid_room_kind", "The room creation type is invalid.");
    }
    if (is_direct || is_private) && request.join_rule != "invite" {
        return error_json(
            "invalid_join_rule",
            "The requested room join rule is not supported.",
        );
    }
    if is_public && request.join_rule != "public" {
        return error_json(
            "invalid_join_rule",
            "The requested room join rule is not supported.",
        );
    }
    if request.invitees.iter().any(|value| value.contains('\0'))
        || request
            .name
            .as_ref()
            .is_some_and(|value| value.contains('\0'))
        || request
            .topic
            .as_ref()
            .is_some_and(|value| value.contains('\0'))
        || request
            .canonical_alias
            .as_ref()
            .is_some_and(|value| value.contains('\0'))
    {
        return error_json(
            "invalid_room_request",
            "The room creation request is invalid.",
        );
    }

    let invitees = match request
        .invitees
        .iter()
        .map(|user_id| UserId::parse(user_id).map(Into::<OwnedUserId>::into))
        .collect::<Result<Vec<_>, _>>()
    {
        Ok(invitees) => invitees,
        Err(_) => return error_json("invalid_invitee", "A Matrix invitee is invalid."),
    };
    if is_direct && invitees.len() != 1 {
        return error_json(
            "invalid_direct_invitee",
            "A direct conversation requires exactly one Matrix user.",
        );
    }

    let history_visibility = match request.history_visibility.as_str() {
        "invited" => HistoryVisibility::Invited,
        "joined" => HistoryVisibility::Joined,
        "shared" => HistoryVisibility::Shared,
        "worldReadable" => HistoryVisibility::WorldReadable,
        _ => {
            return error_json(
                "invalid_history_visibility",
                "The room history visibility is invalid.",
            );
        }
    };

    let client = unsafe { &mut *client };
    let Some(matrix_client) = client.client.as_ref() else {
        return error_json("client_closed", "Matrix room creation is unavailable.");
    };
    let mut native_request = create_room::v3::Request::new();
    native_request.name = request.name.filter(|value| !value.trim().is_empty());
    native_request.topic = request.topic.filter(|value| !value.trim().is_empty());
    native_request.invite = invitees.clone();
    native_request.is_direct = is_direct;
    native_request.preset = Some(if is_public {
        create_room::v3::RoomPreset::PublicChat
    } else if is_direct {
        create_room::v3::RoomPreset::TrustedPrivateChat
    } else {
        create_room::v3::RoomPreset::PrivateChat
    });
    native_request.visibility = if is_public {
        Visibility::Public
    } else {
        Visibility::Private
    };
    native_request.initial_state.push(
        InitialStateEvent::with_empty_state_key(RoomJoinRulesEventContent::new(if is_public {
            JoinRule::Public
        } else {
            JoinRule::Invite
        }))
        .to_raw_any(),
    );
    native_request.initial_state.push(
        InitialStateEvent::with_empty_state_key(RoomHistoryVisibilityEventContent::new(
            history_visibility,
        ))
        .to_raw_any(),
    );
    if request.encryption_enabled {
        native_request.initial_state.push(
            InitialStateEvent::with_empty_state_key(
                RoomEncryptionEventContent::with_recommended_defaults(),
            )
            .to_raw_any(),
        );
    }
    if let Some(alias) = request.canonical_alias {
        let Ok(alias) = RoomAliasId::parse(alias) else {
            return error_json("invalid_room_alias", "The Matrix room address is invalid.");
        };
        let Some(user_id) = matrix_client.user_id() else {
            return error_json(
                "authentication_required",
                "The Matrix session is unavailable.",
            );
        };
        if alias.server_name() != user_id.server_name() {
            return error_json(
                "invalid_room_alias",
                "The room address must use the signed-in account server.",
            );
        }
        native_request.room_alias_name = Some(alias.alias().to_owned());
    }

    let previous_access_token = matrix_client
        .matrix_auth()
        .session()
        .map(|session| session.tokens.access_token);
    let room = match client
        .runtime
        .block_on(matrix_client.create_room(native_request))
    {
        Ok(room) => room,
        Err(_) => {
            return error_json(
                "room_create_failed",
                "The Matrix room could not be created.",
            );
        }
    };
    if is_direct
        && client
            .runtime
            .block_on(
                matrix_client
                    .account()
                    .mark_as_dm(room.room_id(), &invitees),
            )
            .is_err()
    {
        return error_json(
            "direct_metadata_failed",
            "The direct conversation was created but could not be marked as a DM.",
        );
    }
    if persist_session_if_access_token_changed(
        &client.runtime,
        matrix_client,
        previous_access_token.as_deref(),
    )
    .is_err()
    {
        return error_json(
            "session_persist_failed",
            "Could not save the refreshed Matrix session.",
        );
    }

    ok_json(json!({"roomId": room.room_id().as_str(), "isDirect": is_direct}))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_respond_to_invite(
    client: *mut KiteMatrixClient,
    room_id: *const c_char,
    accept: u8,
) -> *mut c_char {
    if client.is_null() {
        return error_json("client_closed", "Matrix room invites are unavailable.");
    }
    let Some(room_id) = (unsafe { required_utf8(room_id) }) else {
        return error_json("invalid_room", "The Matrix room is invalid.");
    };
    if accept > 1 {
        return error_json(
            "invalid_invite_action",
            "The Matrix invite action is invalid.",
        );
    }
    let Ok(room_id) = RoomId::parse(room_id) else {
        return error_json("invalid_room", "The Matrix room is invalid.");
    };

    let client = unsafe { &mut *client };
    let Some(matrix_client) = client.client.as_ref() else {
        return error_json("client_closed", "Matrix room invites are unavailable.");
    };
    let Some(room) = matrix_client.get_room(&room_id) else {
        return error_json("room_not_found", "The Matrix room invite is unavailable.");
    };
    let previous_access_token = matrix_client
        .matrix_auth()
        .session()
        .map(|session| session.tokens.access_token);
    let result = if accept == 1 {
        client.runtime.block_on(room.join())
    } else {
        client.runtime.block_on(room.leave())
    };
    if result.is_err() {
        return error_json(
            "invite_action_failed",
            if accept == 1 {
                "The Matrix room invite could not be accepted."
            } else {
                "The Matrix room invite could not be declined."
            },
        );
    }
    if persist_session_if_access_token_changed(
        &client.runtime,
        matrix_client,
        previous_access_token.as_deref(),
    )
    .is_err()
    {
        return error_json(
            "session_persist_failed",
            "Could not save the refreshed Matrix session.",
        );
    }

    ok_json(json!({
        "roomId": room_id.as_str(),
        "accepted": accept == 1,
    }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_set_room_favourite(
    client: *mut KiteMatrixClient,
    room_id: *const c_char,
    is_favourite: u8,
) -> *mut c_char {
    if client.is_null() {
        return error_json("client_closed", "Matrix room favourites are unavailable.");
    }
    let Some(room_id) = (unsafe { required_utf8(room_id) }) else {
        return error_json("invalid_room", "The Matrix room is invalid.");
    };
    if room_id.is_empty() || is_favourite > 1 {
        return error_json(
            "invalid_room",
            "The Matrix room favourite state is invalid.",
        );
    }
    let Ok(room_id) = RoomId::parse(room_id) else {
        return error_json("invalid_room", "The Matrix room is invalid.");
    };

    let client = unsafe { &mut *client };
    let Some(matrix_client) = client.client.as_ref() else {
        return error_json("client_closed", "Matrix room favourites are unavailable.");
    };
    let Some(room) = matrix_client.get_room(&room_id) else {
        return error_json("room_not_found", "The Matrix room is unavailable.");
    };
    let previous_access_token = matrix_client
        .matrix_auth()
        .session()
        .map(|session| session.tokens.access_token);
    if client
        .runtime
        .block_on(room.set_is_favourite(is_favourite == 1, None))
        .is_err()
    {
        return error_json(
            "favourite_failed",
            "The Matrix room favourite state could not be saved.",
        );
    }
    if persist_session_if_access_token_changed(
        &client.runtime,
        matrix_client,
        previous_access_token.as_deref(),
    )
    .is_err()
    {
        return error_json(
            "session_persist_failed",
            "Could not save the refreshed Matrix session.",
        );
    }

    ok_json(json!({"isFavourite": is_favourite == 1}))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_mark_room_read(
    client: *mut KiteMatrixClient,
    room_id: *const c_char,
    event_id: *const c_char,
) -> *mut c_char {
    if client.is_null() {
        return error_json("client_closed", "Matrix read receipts are unavailable.");
    }
    let Some(room_id) = (unsafe { required_utf8(room_id) }) else {
        return error_json("invalid_room", "The Matrix room is invalid.");
    };
    let Some(event_id) = (unsafe { required_utf8(event_id) }) else {
        return error_json("invalid_event", "The Matrix event is invalid.");
    };
    let Ok(room_id) = RoomId::parse(room_id) else {
        return error_json("invalid_room", "The Matrix room is invalid.");
    };
    let Ok(event_id) = EventId::parse(event_id) else {
        return error_json("invalid_event", "The Matrix event is invalid.");
    };

    let client = unsafe { &mut *client };
    let Some(matrix_client) = client.client.as_ref() else {
        return error_json("client_closed", "Matrix read receipts are unavailable.");
    };
    let Some(room) = matrix_client.get_room(&room_id) else {
        return error_json("room_not_found", "The Matrix room is unavailable.");
    };
    let previous_access_token = matrix_client
        .matrix_auth()
        .session()
        .map(|session| session.tokens.access_token);
    if client
        .runtime
        .block_on(room.send_single_receipt(
            create_receipt::v3::ReceiptType::Read,
            ReceiptThread::Unthreaded,
            event_id.clone(),
        ))
        .is_err()
    {
        return error_json(
            "receipt_failed",
            "The Matrix read receipt could not be saved.",
        );
    }
    if persist_session_if_access_token_changed(
        &client.runtime,
        matrix_client,
        previous_access_token.as_deref(),
    )
    .is_err()
    {
        return error_json(
            "session_persist_failed",
            "Could not save the refreshed Matrix session.",
        );
    }

    ok_json(json!({
        "roomId": room_id.as_str(),
        "eventId": event_id.as_str(),
    }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_room_members(
    client: *mut KiteMatrixClient,
    room_id: *const c_char,
) -> *mut c_char {
    if client.is_null() {
        return ptr::null_mut();
    }
    let Some(room_id) = (unsafe { required_utf8(room_id) }) else {
        return ptr::null_mut();
    };
    if room_id.is_empty() {
        return ptr::null_mut();
    }
    let Ok(room_id) = RoomId::parse(room_id) else {
        return ptr::null_mut();
    };

    let client = unsafe { &mut *client };
    let Some(matrix_client) = client.client.as_ref() else {
        return ptr::null_mut();
    };
    let Some(room) = matrix_client.get_room(&room_id) else {
        return error_json("room_not_found", "The Matrix room is unavailable.");
    };
    let previous_access_token = matrix_client
        .matrix_auth()
        .session()
        .map(|session| session.tokens.access_token);
    let members = match client.runtime.block_on(room.members(RoomMemberships::JOIN)) {
        Ok(members) => members,
        Err(error) => return sync_error_json(&error),
    };
    if persist_session_if_access_token_changed(
        &client.runtime,
        matrix_client,
        previous_access_token.as_deref(),
    )
    .is_err()
    {
        return error_json(
            "session_persist_failed",
            "Could not save the refreshed Matrix session.",
        );
    }

    let members = members
        .into_iter()
        .map(|member| {
            let power_level = match member.power_level() {
                UserPowerLevel::Infinite => 100_i64,
                UserPowerLevel::Int(value) => i64::from(value),
                _ => 0_i64,
            };
            json!({
                "userId": member.user_id().as_str(),
                "displayName": member
                    .display_name()
                    .filter(|name| !name.trim().is_empty())
                    .unwrap_or(member.user_id().as_str()),
                "powerLevel": power_level,
            })
        })
        .collect::<Vec<_>>();

    ok_json(json!({
        "roomId": room_id.as_str(),
        "members": members,
    }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_invite_room_member(
    client: *mut KiteMatrixClient,
    room_id: *const c_char,
    user_id: *const c_char,
) -> *mut c_char {
    if client.is_null() {
        return error_json(
            "client_closed",
            "Matrix room member invitations are unavailable.",
        );
    }
    let Some(room_id) = (unsafe { required_utf8(room_id) }) else {
        return error_json("invalid_room", "The Matrix room is invalid.");
    };
    let Some(user_id) = (unsafe { required_utf8(user_id) }) else {
        return error_json("invalid_user", "The Matrix user is invalid.");
    };
    let Ok(room_id) = RoomId::parse(room_id) else {
        return error_json("invalid_room", "The Matrix room is invalid.");
    };
    let Ok(user_id) = UserId::parse(user_id) else {
        return error_json("invalid_user", "The Matrix user is invalid.");
    };

    let client = unsafe { &mut *client };
    let Some(matrix_client) = client.client.as_ref() else {
        return error_json(
            "client_closed",
            "Matrix room member invitations are unavailable.",
        );
    };
    let Some(room) = matrix_client.get_room(&room_id) else {
        return error_json("room_not_found", "The Matrix room is unavailable.");
    };
    let previous_access_token = matrix_client
        .matrix_auth()
        .session()
        .map(|session| session.tokens.access_token);
    if client
        .runtime
        .block_on(room.invite_user_by_id(&user_id))
        .is_err()
    {
        return error_json(
            "member_invite_failed",
            "The Matrix user could not be invited to this room.",
        );
    }
    if persist_session_if_access_token_changed(
        &client.runtime,
        matrix_client,
        previous_access_token.as_deref(),
    )
    .is_err()
    {
        return error_json(
            "session_persist_failed",
            "Could not save the refreshed Matrix session.",
        );
    }

    ok_json(json!({
        "roomId": room_id.as_str(),
        "userId": user_id.as_str(),
    }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_room_member_permissions(
    client: *mut KiteMatrixClient,
    room_id: *const c_char,
    actor_user_id: *const c_char,
    target_user_id: *const c_char,
) -> *mut c_char {
    if client.is_null() {
        return error_json("client_closed", "Matrix room moderation is unavailable.");
    }
    let Some(room_id) = (unsafe { required_utf8(room_id) }) else {
        return error_json("invalid_room", "The Matrix room is invalid.");
    };
    let Some(actor_user_id) = (unsafe { required_utf8(actor_user_id) }) else {
        return error_json("invalid_user", "The Matrix user is invalid.");
    };
    let Some(target_user_id) = (unsafe { required_utf8(target_user_id) }) else {
        return error_json("invalid_user", "The Matrix user is invalid.");
    };
    let Ok(room_id) = RoomId::parse(room_id) else {
        return error_json("invalid_room", "The Matrix room is invalid.");
    };
    let Ok(actor_user_id) = UserId::parse(actor_user_id) else {
        return error_json("invalid_user", "The Matrix user is invalid.");
    };
    let Ok(target_user_id) = UserId::parse(target_user_id) else {
        return error_json("invalid_user", "The Matrix user is invalid.");
    };

    let client = unsafe { &mut *client };
    let Some(matrix_client) = client.client.as_ref() else {
        return error_json("client_closed", "Matrix room moderation is unavailable.");
    };
    let Some(room) = matrix_client.get_room(&room_id) else {
        return error_json("room_not_found", "The Matrix room is unavailable.");
    };
    let previous_access_token = matrix_client
        .matrix_auth()
        .session()
        .map(|session| session.tokens.access_token);
    let power_levels = match client.runtime.block_on(room.power_levels()) {
        Ok(power_levels) => power_levels,
        Err(_) => {
            return error_json(
                "power_levels_unavailable",
                "Matrix room permissions are unavailable.",
            );
        }
    };
    if persist_session_if_access_token_changed(
        &client.runtime,
        matrix_client,
        previous_access_token.as_deref(),
    )
    .is_err()
    {
        return error_json(
            "session_persist_failed",
            "Could not save the refreshed Matrix session.",
        );
    }
    let actor_power_level = match power_levels.for_user(&actor_user_id) {
        UserPowerLevel::Infinite => 100_i64,
        UserPowerLevel::Int(value) => i64::from(value),
        _ => 0_i64,
    };

    ok_json(json!({
        "roomId": room_id.as_str(),
        "targetUserId": target_user_id.as_str(),
        "actorPowerLevel": actor_power_level,
        "canInvite": power_levels.user_can_invite(&actor_user_id),
        "canChangePowerLevel": power_levels
            .user_can_change_user_power_level(&actor_user_id, &target_user_id),
        "canKick": power_levels.user_can_kick_user(&actor_user_id, &target_user_id),
        "canBan": power_levels.user_can_ban_user(&actor_user_id, &target_user_id),
        "canUnban": power_levels.user_can_unban_user(&actor_user_id, &target_user_id),
    }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_moderate_room_member(
    client: *mut KiteMatrixClient,
    room_id: *const c_char,
    user_id: *const c_char,
    action: *const c_char,
    power_level: i64,
    reason: *const c_char,
) -> *mut c_char {
    if client.is_null() {
        return error_json("client_closed", "Matrix room moderation is unavailable.");
    }
    let Some(room_id) = (unsafe { required_utf8(room_id) }) else {
        return error_json("invalid_room", "The Matrix room is invalid.");
    };
    let Some(user_id) = (unsafe { required_utf8(user_id) }) else {
        return error_json("invalid_user", "The Matrix user is invalid.");
    };
    let Some(action) = (unsafe { required_utf8(action) }) else {
        return error_json("invalid_action", "The Matrix room action is invalid.");
    };
    let reason = unsafe { required_utf8(reason) }
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let Ok(room_id) = RoomId::parse(room_id) else {
        return error_json("invalid_room", "The Matrix room is invalid.");
    };
    let Ok(user_id) = UserId::parse(user_id) else {
        return error_json("invalid_user", "The Matrix user is invalid.");
    };

    let client = unsafe { &mut *client };
    let Some(matrix_client) = client.client.as_ref() else {
        return error_json("client_closed", "Matrix room moderation is unavailable.");
    };
    let Some(room) = matrix_client.get_room(&room_id) else {
        return error_json("room_not_found", "The Matrix room is unavailable.");
    };
    let previous_access_token = matrix_client
        .matrix_auth()
        .session()
        .map(|session| session.tokens.access_token);

    let result = match action {
        "set_power_level" => match Int::try_from(power_level) {
            Ok(power_level) => client
                .runtime
                .block_on(room.update_power_levels(vec![(&user_id, power_level)]))
                .map(|_| ()),
            Err(_) => {
                return error_json("invalid_power_level", "The Matrix power level is invalid.");
            }
        },
        "kick" => client.runtime.block_on(room.kick_user(&user_id, reason)),
        "ban" => client.runtime.block_on(room.ban_user(&user_id, reason)),
        "unban" => client.runtime.block_on(room.unban_user(&user_id, reason)),
        _ => return error_json("invalid_action", "The Matrix room action is invalid."),
    };
    if result.is_err() {
        return error_json(
            "member_moderation_failed",
            "The Matrix room member action could not be completed.",
        );
    }
    if persist_session_if_access_token_changed(
        &client.runtime,
        matrix_client,
        previous_access_token.as_deref(),
    )
    .is_err()
    {
        return error_json(
            "session_persist_failed",
            "Could not save the refreshed Matrix session.",
        );
    }

    ok_json(json!({
        "roomId": room_id.as_str(),
        "userId": user_id.as_str(),
        "action": action,
    }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_manage_room(
    client: *mut KiteMatrixClient,
    room_id: *const c_char,
    action: *const c_char,
    user_id: *const c_char,
    reason: *const c_char,
) -> *mut c_char {
    if client.is_null() {
        return error_json("client_closed", "Matrix room management is unavailable.");
    }
    let Some(room_id) = (unsafe { required_utf8(room_id) }) else {
        return error_json("invalid_room", "The Matrix room is invalid.");
    };
    let Some(action) = (unsafe { required_utf8(action) }) else {
        return error_json("invalid_action", "The Matrix room action is invalid.");
    };
    let user_id = unsafe { required_utf8(user_id) }
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let reason = unsafe { required_utf8(reason) }
        .map(str::trim)
        .unwrap_or_default()
        .to_owned();
    let Ok(room_id) = RoomId::parse(room_id) else {
        return error_json("invalid_room", "The Matrix room is invalid.");
    };

    let client = unsafe { &mut *client };
    let Some(matrix_client) = client.client.as_ref() else {
        return error_json("client_closed", "Matrix room management is unavailable.");
    };
    let Some(room) = matrix_client.get_room(&room_id) else {
        return error_json("room_not_found", "The Matrix room is unavailable.");
    };
    let previous_access_token = matrix_client
        .matrix_auth()
        .session()
        .map(|session| session.tokens.access_token);

    let reported_user_id = match action {
        "report_room" => {
            if client.runtime.block_on(room.report_room(reason)).is_err() {
                return error_json(
                    "room_management_failed",
                    "The Matrix room action could not be completed.",
                );
            }
            None
        }
        "report_user" => {
            let Some(user_id) = user_id else {
                return error_json("invalid_user", "The Matrix user is invalid.");
            };
            let Ok(user_id) = UserId::parse(user_id) else {
                return error_json("invalid_user", "The Matrix user is invalid.");
            };
            let request = report_user::v3::Request::new(user_id.to_owned(), reason);
            if client
                .runtime
                .block_on(async { matrix_client.send(request).await })
                .is_err()
            {
                return error_json(
                    "room_management_failed",
                    "The Matrix room action could not be completed.",
                );
            }
            Some(user_id.to_owned())
        }
        "leave" => {
            let result = client.runtime.block_on(async {
                room.leave().await?;
                room.set_is_direct(false).await
            });
            if result.is_err() {
                return error_json(
                    "room_management_failed",
                    "The Matrix room action could not be completed.",
                );
            }
            None
        }
        "forget" => {
            if client.runtime.block_on(room.forget()).is_err() {
                return error_json(
                    "room_management_failed",
                    "The Matrix room action could not be completed.",
                );
            }
            None
        }
        _ => return error_json("invalid_action", "The Matrix room action is invalid."),
    };

    if persist_session_if_access_token_changed(
        &client.runtime,
        matrix_client,
        previous_access_token.as_deref(),
    )
    .is_err()
    {
        return error_json(
            "session_persist_failed",
            "Could not save the refreshed Matrix session.",
        );
    }

    ok_json(json!({
        "roomId": room_id.as_str(),
        "action": action,
        "userId": reported_user_id.as_deref().map(UserId::as_str),
    }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_profile(
    client: *mut KiteMatrixClient,
    user_id: *const c_char,
    action: *const c_char,
    value: *const c_char,
) -> *mut c_char {
    if client.is_null() {
        return error_json("client_closed", "Matrix profiles are unavailable.");
    }
    let Some(action) = (unsafe { required_utf8(action) }) else {
        return error_json("invalid_action", "The Matrix profile action is invalid.");
    };
    let user_id = unsafe { required_utf8(user_id) };
    let raw_value = unsafe { required_utf8(value) };
    let value = raw_value.map(str::trim);

    let client = unsafe { &mut *client };
    let Some(matrix_client) = client.client.as_ref() else {
        return error_json("client_closed", "Matrix profiles are unavailable.");
    };
    let previous_access_token = matrix_client
        .matrix_auth()
        .session()
        .map(|session| session.tokens.access_token);

    let response = match action {
        "get" => {
            let target_user_id = match user_id {
                Some(user_id) => match UserId::parse(user_id) {
                    Ok(user_id) => user_id,
                    Err(_) => {
                        return error_json("invalid_user", "The Matrix user is invalid.");
                    }
                },
                None => match matrix_client.user_id() {
                    Some(user_id) => user_id.to_owned(),
                    None => {
                        return error_json(
                            "authentication_required",
                            "The Matrix session is unavailable.",
                        );
                    }
                },
            };
            let profile = match client.runtime.block_on(
                matrix_client
                    .account()
                    .fetch_user_profile_of(&target_user_id),
            ) {
                Ok(profile) => profile,
                Err(_) => {
                    return error_json("profile_failed", "The Matrix profile could not be loaded.");
                }
            };
            let display_name = profile
                .get_static::<DisplayName>()
                .ok()
                .flatten()
                .filter(|name| !name.trim().is_empty());
            let avatar_url = profile
                .get_static::<AvatarUrl>()
                .ok()
                .flatten()
                .filter(|url| url.is_valid());
            json!({
                "userId": target_user_id.as_str(),
                "displayName": display_name,
                "avatarUrl": avatar_url.map(|url| url.to_string()),
            })
        }
        "search" => {
            let Some(query) = value.filter(|value| value.len() >= 2) else {
                return error_json(
                    "invalid_search",
                    "The Matrix user search must contain at least two characters.",
                );
            };
            let search = match client
                .runtime
                .block_on(matrix_client.search_users(query, 20))
            {
                Ok(search) => search,
                Err(_) => {
                    return error_json(
                        "profile_failed",
                        "The Matrix user directory could not be searched.",
                    );
                }
            };
            let results = search
                .results
                .into_iter()
                .map(|user| {
                    json!({
                        "userId": user.user_id.as_str(),
                        "displayName": user.display_name.filter(|name| !name.trim().is_empty()),
                        "avatarUrl": user
                            .avatar_url
                            .filter(|url| url.is_valid())
                            .map(|url| url.to_string()),
                    })
                })
                .collect::<Vec<_>>();
            json!({"results": results, "limited": search.limited})
        }
        "devices" => {
            let Some(session) = matrix_client.session_meta() else {
                return error_json(
                    "profile_failed",
                    "The signed-in devices could not be loaded.",
                );
            };
            let current_device_id = session.device_id.clone();
            let user_id = session.user_id.clone();
            let response = match client.runtime.block_on(matrix_client.devices()) {
                Ok(response) => response,
                Err(_) => {
                    return error_json(
                        "profile_failed",
                        "The signed-in devices could not be loaded.",
                    );
                }
            };
            let crypto_devices = client
                .runtime
                .block_on(matrix_client.encryption().get_user_devices(&user_id))
                .ok();
            let devices = response
                .devices
                .into_iter()
                .map(|device| {
                    let verification = crypto_devices
                        .as_ref()
                        .and_then(|devices| devices.get(&device.device_id))
                        .map(|device| {
                            if device.is_verified() {
                                "verified"
                            } else {
                                "unverified"
                            }
                        })
                        .unwrap_or("unknown");
                    let last_seen_at_ms = device.last_seen_ts.map(|timestamp| {
                        let value: u64 = timestamp.get().into();
                        value
                    });
                    json!({
                        "deviceId": device.device_id.as_str(),
                        "displayName": device.display_name,
                        "lastSeenAtMs": last_seen_at_ms,
                        "isCurrent": device.device_id == current_device_id,
                        "verification": verification,
                    })
                })
                .collect::<Vec<_>>();
            json!({"devices": devices})
        }
        "delete_device" => {
            let Some(device_id) =
                user_id.filter(|value| !value.is_empty() && value.trim() == *value)
            else {
                return error_json("invalid_device", "The Matrix device is invalid.");
            };
            let Some(password) = raw_value.filter(|value| !value.is_empty()) else {
                return error_json(
                    "reauthentication_required",
                    "Your account password is required to sign out that device.",
                );
            };
            let Some(session) = matrix_client.session_meta() else {
                return error_json(
                    "authentication_required",
                    "The Matrix session is unavailable.",
                );
            };
            if session.device_id.as_str() == device_id {
                return error_json(
                    "invalid_device",
                    "Use account sign out for the current device.",
                );
            }
            let devices = [OwnedDeviceId::from(device_id.to_owned())];
            let first_attempt = client
                .runtime
                .block_on(matrix_client.delete_devices(&devices, None));
            if let Err(error) = first_attempt {
                let Some(info) = error.as_uiaa_response() else {
                    return error_json(
                        "device_sign_out_failed",
                        "The Matrix device could not be signed out.",
                    );
                };
                let mut password_auth = uiaa::Password::new(
                    uiaa::UserIdentifier::Matrix(uiaa::MatrixUserIdentifier::new(
                        session.user_id.localpart().to_owned(),
                    )),
                    password.to_owned(),
                );
                password_auth.session = info.session.clone();
                let authenticated = client.runtime.block_on(
                    matrix_client
                        .delete_devices(&devices, Some(uiaa::AuthData::Password(password_auth))),
                );
                if authenticated.is_err() {
                    return error_json(
                        "device_sign_out_failed",
                        "The Matrix device could not be signed out.",
                    );
                }
            }
            json!({"action": "delete_device", "deviceId": device_id})
        }
        "ignored_users" => {
            let ignored_users = match client.runtime.block_on(
                matrix_client
                    .account()
                    .account_data::<IgnoredUserListEventContent>(),
            ) {
                Ok(Some(raw_content)) => match raw_content.deserialize() {
                    Ok(content) => content
                        .ignored_users
                        .into_keys()
                        .map(|user_id| user_id.to_string())
                        .collect::<Vec<_>>(),
                    Err(_) => {
                        return error_json(
                            "profile_failed",
                            "The blocked-user list could not be read.",
                        );
                    }
                },
                Ok(None) => Vec::new(),
                Err(_) => {
                    return error_json(
                        "profile_failed",
                        "The blocked-user list could not be read.",
                    );
                }
            };
            json!({"userIds": ignored_users})
        }
        "set_ignored" => {
            let Some(user_id) = user_id else {
                return error_json("invalid_user", "The Matrix user is invalid.");
            };
            let Ok(user_id) = UserId::parse(user_id) else {
                return error_json("invalid_user", "The Matrix user is invalid.");
            };
            let ignored = match value {
                Some("true") => true,
                Some("false") => false,
                _ => {
                    return error_json("invalid_action", "The blocked-user state is invalid.");
                }
            };
            let result = if ignored {
                client
                    .runtime
                    .block_on(matrix_client.account().ignore_user(&user_id))
            } else {
                client
                    .runtime
                    .block_on(matrix_client.account().unignore_user(&user_id))
            };
            if result.is_err() {
                return error_json(
                    "profile_failed",
                    "The blocked-user state could not be updated.",
                );
            }
            json!({
                "action": action,
                "userId": user_id.as_str(),
                "ignored": ignored,
            })
        }
        "set_display_name" => {
            let display_name = value.filter(|value| !value.is_empty());
            if client
                .runtime
                .block_on(matrix_client.account().set_display_name(display_name))
                .is_err()
            {
                return error_json(
                    "profile_failed",
                    "The Matrix display name could not be updated.",
                );
            }
            json!({"action": action})
        }
        "set_avatar" => {
            let avatar = match value.filter(|value| !value.is_empty()) {
                Some(value) => {
                    let avatar = OwnedMxcUri::from(value.to_owned());
                    if !avatar.is_valid() {
                        return error_json("invalid_avatar", "The Matrix avatar URI is invalid.");
                    }
                    Some(avatar)
                }
                None => None,
            };
            if client
                .runtime
                .block_on(matrix_client.account().set_avatar_url(avatar.as_deref()))
                .is_err()
            {
                return error_json("profile_failed", "The Matrix avatar could not be updated.");
            }
            json!({"action": action})
        }
        "open_direct" => {
            let Some(user_id) = user_id else {
                return error_json("invalid_user", "The Matrix user is invalid.");
            };
            let Ok(user_id) = UserId::parse(user_id) else {
                return error_json("invalid_user", "The Matrix user is invalid.");
            };
            let room = match matrix_client.get_dm_room(&user_id) {
                Some(room) => room,
                None => match client.runtime.block_on(matrix_client.create_dm(&user_id)) {
                    Ok(room) => room,
                    Err(_) => {
                        return error_json(
                            "profile_failed",
                            "The direct conversation could not be opened.",
                        );
                    }
                },
            };
            json!({"roomId": room.room_id().as_str()})
        }
        _ => return error_json("invalid_action", "The Matrix profile action is invalid."),
    };

    if persist_session_if_access_token_changed(
        &client.runtime,
        matrix_client,
        previous_access_token.as_deref(),
    )
    .is_err()
    {
        return error_json(
            "session_persist_failed",
            "Could not save the refreshed Matrix session.",
        );
    }

    ok_json(response)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_upload_media(
    client: *mut KiteMatrixClient,
    mime_type: *const c_char,
    data: *const u8,
    data_len: u64,
) -> *mut c_char {
    if client.is_null() {
        return error_json("client_closed", "Matrix media upload is unavailable.");
    }
    let Some(mime_type) = (unsafe { required_utf8(mime_type) }) else {
        return error_json("invalid_media_type", "The media type is invalid.");
    };
    let Ok(mime_type) = mime_type.parse::<mime::Mime>() else {
        return error_json("invalid_media_type", "The media type is invalid.");
    };
    if data_len == 0 || data.is_null() {
        return error_json("invalid_media", "The media file is empty.");
    }
    let Ok(data_len) = usize::try_from(data_len) else {
        return error_json("invalid_media", "The media file is too large.");
    };
    let bytes = unsafe { std::slice::from_raw_parts(data, data_len) }.to_vec();

    let client = unsafe { &mut *client };
    let Some(matrix_client) = client.client.as_ref() else {
        return error_json("client_closed", "Matrix media upload is unavailable.");
    };
    let previous_access_token = matrix_client
        .matrix_auth()
        .session()
        .map(|session| session.tokens.access_token);
    let Ok(response) = client
        .runtime
        .block_on(async { matrix_client.media().upload(&mime_type, bytes, None).await })
    else {
        return error_json(
            "media_upload_failed",
            "The media file could not be uploaded.",
        );
    };
    if persist_session_if_access_token_changed(
        &client.runtime,
        matrix_client,
        previous_access_token.as_deref(),
    )
    .is_err()
    {
        return error_json(
            "session_persist_failed",
            "Could not save the refreshed Matrix session.",
        );
    }

    ok_json(json!({"contentUri": response.content_uri.as_str()}))
}

async fn prefetch_media_item(
    matrix_client: Client,
    content_uri: String,
    source: MediaSource,
    width: UInt,
    height: UInt,
) -> (String, Option<Vec<u8>>) {
    let thumbnail = MediaRequestParameters {
        source: source.clone(),
        format: MediaFormat::Thumbnail(MediaThumbnailSettings::new(width, height)),
    };
    let file = MediaRequestParameters {
        source,
        format: MediaFormat::File,
    };
    let bytes = match matrix_client
        .media()
        .get_media_content(&thumbnail, true)
        .await
    {
        Ok(bytes) if !bytes.is_empty() => Some(bytes),
        _ => matrix_client
            .media()
            .get_media_content(&file, true)
            .await
            .ok()
            .filter(|bytes| !bytes.is_empty()),
    };
    (content_uri, bytes)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_prefetch_media(
    client: *mut KiteMatrixClient,
    content_uris_json: *const c_char,
    width: u64,
    height: u64,
) -> *mut c_char {
    if client.is_null() {
        return error_json("client_closed", "Matrix media prefetch is unavailable.");
    }
    let Some(content_uris_json) = (unsafe { required_utf8(content_uris_json) }) else {
        return error_json(
            "invalid_media",
            "The Matrix media prefetch list is invalid.",
        );
    };
    let Ok(content_uris) = serde_json::from_str::<Vec<String>>(content_uris_json) else {
        return error_json(
            "invalid_media",
            "The Matrix media prefetch list is invalid.",
        );
    };
    if content_uris.len() > 32 {
        return error_json(
            "invalid_media",
            "Matrix media prefetch supports at most 32 items at once.",
        );
    }
    let Some(width) = UInt::new(width) else {
        return error_json("invalid_media_size", "The Matrix media size is invalid.");
    };
    let Some(height) = UInt::new(height) else {
        return error_json("invalid_media_size", "The Matrix media size is invalid.");
    };
    if width == UInt::MIN || height == UInt::MIN {
        return error_json("invalid_media_size", "The Matrix media size is invalid.");
    }

    let mut sources = Vec::with_capacity(content_uris.len());
    for content_uri in content_uris {
        let owned_uri = OwnedMxcUri::from(content_uri.clone());
        if !owned_uri.is_valid() {
            return error_json("invalid_media", "The Matrix media URI is invalid.");
        }
        sources.push((content_uri, MediaSource::Plain(owned_uri)));
    }

    let client = unsafe { &mut *client };
    let Some(matrix_client) = client.client.as_ref() else {
        return error_json("client_closed", "Matrix media prefetch is unavailable.");
    };
    let previous_access_token = matrix_client
        .matrix_auth()
        .session()
        .map(|session| session.tokens.access_token);

    let (items, failed) = client.runtime.block_on(async {
        let mut pending = sources.into_iter();
        let mut tasks = JoinSet::new();
        for _ in 0..KITE_MATRIX_MEDIA_PREFETCH_CONCURRENCY {
            let Some((content_uri, source)) = pending.next() else {
                break;
            };
            tasks.spawn(prefetch_media_item(
                matrix_client.clone(),
                content_uri,
                source,
                width,
                height,
            ));
        }

        let mut items = Vec::new();
        let mut failed = 0usize;
        while let Some(result) = tasks.join_next().await {
            match result {
                Ok((content_uri, Some(bytes))) => items.push(json!({
                    "contentUri": content_uri,
                    "data": BASE64_STANDARD.encode(bytes),
                })),
                _ => failed += 1,
            }
            if let Some((content_uri, source)) = pending.next() {
                tasks.spawn(prefetch_media_item(
                    matrix_client.clone(),
                    content_uri,
                    source,
                    width,
                    height,
                ));
            }
        }
        (items, failed)
    });

    if persist_session_if_access_token_changed(
        &client.runtime,
        matrix_client,
        previous_access_token.as_deref(),
    )
    .is_err()
    {
        return error_json(
            "session_persist_failed",
            "Could not save the refreshed Matrix session.",
        );
    }

    ok_json(json!({
        "requested": items.len() + failed,
        "completed": items.len(),
        "failed": failed,
        "items": items,
    }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_download_media(
    client: *mut KiteMatrixClient,
    content_uri: *const c_char,
    width: u64,
    height: u64,
) -> *mut c_char {
    if client.is_null() {
        return error_json("client_closed", "Matrix media download is unavailable.");
    }
    let Some(content_uri) = (unsafe { required_utf8(content_uri) }) else {
        return error_json("invalid_media", "The Matrix media source is invalid.");
    };
    let source = if content_uri.trim_start().starts_with('{') {
        match serde_json::from_str::<MediaSource>(content_uri) {
            Ok(source) => source,
            Err(_) => {
                return error_json("invalid_media", "The Matrix media source is invalid.");
            }
        }
    } else {
        let content_uri = OwnedMxcUri::from(content_uri.to_owned());
        if !content_uri.is_valid() {
            return error_json("invalid_media", "The Matrix media URI is invalid.");
        }
        MediaSource::Plain(content_uri)
    };
    let Some(width) = UInt::new(width) else {
        return error_json("invalid_media_size", "The Matrix media size is invalid.");
    };
    let Some(height) = UInt::new(height) else {
        return error_json("invalid_media_size", "The Matrix media size is invalid.");
    };
    if width == UInt::MIN || height == UInt::MIN {
        return error_json("invalid_media_size", "The Matrix media size is invalid.");
    }

    let client = unsafe { &mut *client };
    let Some(matrix_client) = client.client.as_ref() else {
        return error_json("client_closed", "Matrix media download is unavailable.");
    };
    let previous_access_token = matrix_client
        .matrix_auth()
        .session()
        .map(|session| session.tokens.access_token);
    let thumbnail = MediaRequestParameters {
        source: source.clone(),
        format: MediaFormat::Thumbnail(MediaThumbnailSettings::new(width, height)),
    };
    let file = MediaRequestParameters {
        source,
        format: MediaFormat::File,
    };
    let result = client.runtime.block_on(async {
        match matrix_client
            .media()
            .get_media_content(&thumbnail, true)
            .await
        {
            Ok(bytes) => Ok(bytes),
            Err(_) => matrix_client.media().get_media_content(&file, true).await,
        }
    });
    let Ok(bytes) = result else {
        return error_json(
            "media_download_failed",
            "The Matrix media file could not be downloaded.",
        );
    };
    if bytes.is_empty() {
        return error_json("media_download_failed", "The Matrix media file is empty.");
    }
    if persist_session_if_access_token_changed(
        &client.runtime,
        matrix_client,
        previous_access_token.as_deref(),
    )
    .is_err()
    {
        return error_json(
            "session_persist_failed",
            "Could not save the refreshed Matrix session.",
        );
    }

    ok_json(json!({"data": BASE64_STANDARD.encode(bytes)}))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_room_settings(
    client: *mut KiteMatrixClient,
    room_id: *const c_char,
    action: *const c_char,
    value: *const c_char,
) -> *mut c_char {
    if client.is_null() {
        return error_json("client_closed", "Matrix room settings are unavailable.");
    }
    let Some(room_id) = (unsafe { required_utf8(room_id) }) else {
        return error_json("invalid_room", "The Matrix room is invalid.");
    };
    let Some(action) = (unsafe { required_utf8(action) }) else {
        return error_json("invalid_action", "The Matrix room setting is invalid.");
    };
    let value = unsafe { required_utf8(value) }.map(str::trim);
    let Ok(room_id) = RoomId::parse(room_id) else {
        return error_json("invalid_room", "The Matrix room is invalid.");
    };

    let client = unsafe { &mut *client };
    let Some(matrix_client) = client.client.as_ref() else {
        return error_json("client_closed", "Matrix room settings are unavailable.");
    };
    let Some(room) = matrix_client.get_room(&room_id) else {
        return error_json("room_not_found", "The Matrix room is unavailable.");
    };

    if action == "get" {
        let is_direct = match client.runtime.block_on(room.is_direct()) {
            Ok(value) => value,
            Err(_) => {
                return error_json(
                    "room_settings_failed",
                    "The Matrix room settings could not be loaded.",
                );
            }
        };
        let notification_mode = client
            .runtime
            .block_on(room.notification_mode())
            .unwrap_or(RoomNotificationMode::AllMessages);
        let direct_user_ids = room
            .direct_targets()
            .into_iter()
            .filter_map(|target| target.into_user_id())
            .map(|user_id| user_id.to_string())
            .collect::<Vec<_>>();
        return ok_json(json!({
            "roomId": room_id.as_str(),
            "name": room.name(),
            "topic": room.topic(),
            "avatarUrl": room.avatar_url().map(|url| url.to_string()),
            "canonicalAlias": room.canonical_alias().map(|alias| alias.to_string()),
            "joinRule": room.join_rule().map(|rule| rule.as_str().to_owned()).unwrap_or_else(|| "invite".to_owned()),
            "encryptionEnabled": room.encryption_state().is_encrypted(),
            "historyVisibility": room.history_visibility_or_default().as_str(),
            "notificationMode": match notification_mode {
                RoomNotificationMode::AllMessages => "allMessages",
                RoomNotificationMode::MentionsAndKeywordsOnly => "mentionsOnly",
                RoomNotificationMode::Mute => "mute",
            },
            "isDirect": is_direct,
            "directUserIds": direct_user_ids,
        }));
    }

    let previous_access_token = matrix_client
        .matrix_auth()
        .session()
        .map(|session| session.tokens.access_token);
    let result = match action {
        "set_name" => client
            .runtime
            .block_on(room.set_name(value.unwrap_or_default().to_owned()))
            .map(|_| ()),
        "set_topic" => client
            .runtime
            .block_on(room.set_room_topic(value.unwrap_or_default()))
            .map(|_| ()),
        "set_avatar" => {
            if let Some(value) = value.filter(|value| !value.is_empty()) {
                let avatar = OwnedMxcUri::from(value.to_owned());
                if !avatar.is_valid() {
                    return error_json("invalid_avatar", "The Matrix avatar URI is invalid.");
                }
                client
                    .runtime
                    .block_on(room.set_avatar_url(&avatar, None))
                    .map(|_| ())
            } else {
                client.runtime.block_on(room.remove_avatar()).map(|_| ())
            }
        }
        "set_canonical_alias" => {
            let alias = match value.filter(|value| !value.is_empty()) {
                Some(value) => match RoomAliasId::parse(value) {
                    Ok(alias) => Some(alias),
                    Err(_) => {
                        return error_json(
                            "invalid_room_alias",
                            "The Matrix room address is invalid.",
                        );
                    }
                },
                None => None,
            };
            client.runtime.block_on(
                room.privacy_settings()
                    .update_canonical_alias(alias, room.alt_aliases()),
            )
        }
        "set_join_rule" => {
            let join_rule = match value {
                Some("invite") => JoinRule::Invite,
                Some("public") => JoinRule::Public,
                _ => {
                    return error_json(
                        "invalid_join_rule",
                        "The Matrix room join rule is invalid.",
                    );
                }
            };
            client
                .runtime
                .block_on(room.privacy_settings().update_join_rule(join_rule))
        }
        "enable_encryption" => client.runtime.block_on(room.enable_encryption()),
        "set_history_visibility" => {
            let visibility = match value {
                Some("invited") => HistoryVisibility::Invited,
                Some("joined") => HistoryVisibility::Joined,
                Some("shared") => HistoryVisibility::Shared,
                Some("worldReadable") => HistoryVisibility::WorldReadable,
                _ => {
                    return error_json(
                        "invalid_history_visibility",
                        "The Matrix room history visibility is invalid.",
                    );
                }
            };
            client.runtime.block_on(
                room.privacy_settings()
                    .update_room_history_visibility(visibility),
            )
        }
        "set_notification_mode" => {
            let mode = match value {
                Some("allMessages") => RoomNotificationMode::AllMessages,
                Some("mentionsOnly") => RoomNotificationMode::MentionsAndKeywordsOnly,
                Some("mute") => RoomNotificationMode::Mute,
                _ => {
                    return error_json(
                        "invalid_notification_mode",
                        "The Matrix room notification mode is invalid.",
                    );
                }
            };
            let notification_result = client.runtime.block_on(async {
                matrix_client
                    .notification_settings()
                    .await
                    .set_room_notification_mode(&room_id, mode)
                    .await
            });
            if notification_result.is_err() {
                return error_json(
                    "room_settings_failed",
                    "The Matrix room setting could not be updated.",
                );
            }
            Ok(())
        }
        _ => return error_json("invalid_action", "The Matrix room setting is invalid."),
    };
    if result.is_err() {
        return error_json(
            "room_settings_failed",
            "The Matrix room setting could not be updated.",
        );
    }
    if persist_session_if_access_token_changed(
        &client.runtime,
        matrix_client,
        previous_access_token.as_deref(),
    )
    .is_err()
    {
        return error_json(
            "session_persist_failed",
            "Could not save the refreshed Matrix session.",
        );
    }
    ok_json(json!({"roomId": room_id.as_str(), "action": action}))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_paginate_backwards(
    client: *mut KiteMatrixClient,
    room_id: *const c_char,
) -> *mut c_char {
    if client.is_null() {
        return ptr::null_mut();
    }
    let Some(room_id) = (unsafe { required_utf8(room_id) }) else {
        return ptr::null_mut();
    };
    if room_id.is_empty() {
        return ptr::null_mut();
    }
    let Ok(room_id) = RoomId::parse(room_id) else {
        return ptr::null_mut();
    };

    let client = unsafe { &mut *client };
    let Some(matrix_client) = client.client.as_ref() else {
        return ptr::null_mut();
    };
    let Some(room) = matrix_client.get_room(&room_id) else {
        return ptr::null_mut();
    };
    let from = client
        .backwards_pagination_tokens
        .get(room_id.as_str())
        .cloned();
    let mut options = MessagesOptions::backward().from(from.as_deref());
    options.limit = UInt::from(30_u8);
    let previous_access_token = matrix_client
        .matrix_auth()
        .session()
        .map(|session| session.tokens.access_token);
    let messages = match client.runtime.block_on(async {
        tokio::time::timeout(Duration::from_secs(45), room.messages(options)).await
    }) {
        Ok(Ok(messages)) => messages,
        Ok(Err(error)) => {
            return json_to_c_string(&json!({
                "error": format!("pagination failed: {error}"),
            }));
        }
        Err(_) => {
            return json_to_c_string(&json!({
                "error": "pagination timed out",
            }));
        }
    };
    if persist_session_if_access_token_changed(
        &client.runtime,
        matrix_client,
        previous_access_token.as_deref(),
    )
    .is_err()
    {
        return json_to_c_string(&json!({
            "error": "session persistence failed after token refresh",
        }));
    }

    let reached_start = messages.end.is_none()
        || messages.chunk.is_empty()
        || messages.end.as_deref() == from.as_deref();
    if let Some(end) = messages.end.as_ref().filter(|end| !end.is_empty()) {
        client
            .backwards_pagination_tokens
            .insert(room_id.to_string(), end.clone());
    } else {
        client.backwards_pagination_tokens.remove(room_id.as_str());
    }

    json_to_c_string(&json!({
        "roomId": room_id.as_str(),
        "reachedStart": reached_start,
        "events": timeline_events_json(&client.runtime, Some(&room), messages.chunk.iter()),
    }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_string_free(value: *mut c_char) {
    if value.is_null() {
        return;
    }
    drop(unsafe { CString::from_raw(value) });
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_free(client: *mut KiteMatrixClient) {
    if client.is_null() {
        return;
    }
    let mut client = unsafe { Box::from_raw(client) };
    if let Some(matrix_client) = client.client.take() {
        let _runtime_guard = client.runtime.enter();
        drop(matrix_client);
    }
}

#[cfg(test)]
mod tests {
    use std::ffi::CString;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    use super::*;

    #[test]
    fn cold_sync_replaces_stale_backwards_pagination_tokens() {
        let mut tokens = HashMap::from([
            ("!old:example.org".to_owned(), "stale-token".to_owned()),
            ("!kept:example.org".to_owned(), "older-token".to_owned()),
        ]);

        replace_backwards_pagination_tokens(
            &mut tokens,
            [
                ("!kept:example.org", Some("fresh-token")),
                ("!empty:example.org", None),
                ("!blank:example.org", Some("")),
            ],
        );

        assert_eq!(tokens.len(), 1);
        assert_eq!(
            tokens.get("!kept:example.org").map(String::as_str),
            Some("fresh-token")
        );
        assert!(!tokens.contains_key("!old:example.org"));
        assert!(!tokens.contains_key("!empty:example.org"));
        assert!(!tokens.contains_key("!blank:example.org"));
    }

    fn temporary_store() -> std::path::PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!("kite-matrix-{}-{nonce}", std::process::id()))
    }

    #[test]
    fn abi_version_is_pinned() {
        assert_eq!(kite_matrix_abi_version(), 27);
    }

    #[test]
    fn constructs_encrypted_sdk_store_and_releases_client() {
        let homeserver = CString::new("http://localhost:8008").unwrap();
        let store = temporary_store();
        let store_text = CString::new(store.to_string_lossy().as_bytes()).unwrap();
        let passphrase = CString::new("deterministic-test-store-secret").unwrap();

        let client = unsafe {
            kite_matrix_client_new(
                homeserver.as_ptr(),
                store_text.as_ptr(),
                passphrase.as_ptr(),
            )
        };
        assert!(!client.is_null());
        assert!(store.exists());

        unsafe { kite_matrix_client_free(client) };
        fs::remove_dir_all(store).unwrap();
    }

    #[test]
    fn encrypted_store_rejects_the_wrong_passphrase() {
        let homeserver = CString::new("http://localhost:8008").unwrap();
        let store = temporary_store();
        let store_text = CString::new(store.to_string_lossy().as_bytes()).unwrap();
        let first_passphrase = CString::new("first-deterministic-secret").unwrap();
        let wrong_passphrase = CString::new("wrong-deterministic-secret").unwrap();

        let first = unsafe {
            kite_matrix_client_new(
                homeserver.as_ptr(),
                store_text.as_ptr(),
                first_passphrase.as_ptr(),
            )
        };
        assert!(!first.is_null());
        unsafe { kite_matrix_client_free(first) };

        let wrong = unsafe {
            kite_matrix_client_new(
                homeserver.as_ptr(),
                store_text.as_ptr(),
                wrong_passphrase.as_ptr(),
            )
        };
        assert!(wrong.is_null());

        let reopened = unsafe {
            kite_matrix_client_new(
                homeserver.as_ptr(),
                store_text.as_ptr(),
                first_passphrase.as_ptr(),
            )
        };
        assert!(!reopened.is_null());
        unsafe { kite_matrix_client_free(reopened) };
        fs::remove_dir_all(store).unwrap();
    }

    #[test]
    fn rejects_missing_or_empty_store_secret() {
        let homeserver = CString::new("http://localhost:8008").unwrap();
        let store = CString::new(temporary_store().to_string_lossy().as_bytes()).unwrap();
        let empty = CString::new("").unwrap();

        let missing =
            unsafe { kite_matrix_client_new(homeserver.as_ptr(), store.as_ptr(), ptr::null()) };
        assert!(missing.is_null());

        let empty_secret =
            unsafe { kite_matrix_client_new(homeserver.as_ptr(), store.as_ptr(), empty.as_ptr()) };
        assert!(empty_secret.is_null());
    }

    #[test]
    fn reply_content_preserves_matrix_relation() {
        let reply_to = EventId::parse("$original:kite.test").unwrap();
        let content = text_message_content("Reply body", Some(reply_to), None);
        let serialized = serde_json::to_value(content).unwrap();
        assert_eq!(serialized["body"], "Reply body");
        assert_eq!(
            serialized["m.relates_to"]["m.in_reply_to"]["event_id"],
            "$original:kite.test"
        );
    }

    #[test]
    fn replacement_content_preserves_matrix_relation_and_new_content() {
        let target = EventId::parse("$original:kite.test").unwrap();
        let content = text_message_content("Edited body", None, Some(target));
        let serialized = serde_json::to_value(content).unwrap();
        assert_eq!(serialized["m.new_content"]["body"], "Edited body");
        assert_eq!(serialized["m.relates_to"]["rel_type"], "m.replace");
        assert_eq!(
            serialized["m.relates_to"]["event_id"],
            "$original:kite.test"
        );
    }

    #[test]
    fn sync_and_pagination_reject_missing_clients() {
        let room_id = CString::new("!room:kite.test").unwrap();
        let body = CString::new("hello").unwrap();
        let username = CString::new("@alice:kite.test").unwrap();
        let password = CString::new("password").unwrap();
        let login = unsafe {
            kite_matrix_client_login_password(ptr::null_mut(), username.as_ptr(), password.as_ptr())
        };
        let logout = unsafe { kite_matrix_client_logout(ptr::null_mut()) };
        let transaction_id = CString::new("kite-test-transaction").unwrap();
        let send = unsafe {
            kite_matrix_client_send_text(
                ptr::null_mut(),
                room_id.as_ptr(),
                transaction_id.as_ptr(),
                body.as_ptr(),
                ptr::null(),
                ptr::null(),
            )
        };
        let sync = unsafe { kite_matrix_client_sync_once(ptr::null_mut(), 0, ptr::null(), 20) };
        let favourite =
            unsafe { kite_matrix_client_set_room_favourite(ptr::null_mut(), room_id.as_ptr(), 1) };
        let create_request = CString::new(
            r#"{"kind":"privateRoom","name":"Test","topic":null,"invitees":[],"joinRule":"invite","encryptionEnabled":true,"historyVisibility":"joined","canonicalAlias":null,"parentSpaceId":null}"#,
        )
        .unwrap();
        let create =
            unsafe { kite_matrix_client_create_room(ptr::null_mut(), create_request.as_ptr()) };
        let event_id = CString::new("$event:kite.test").unwrap();
        let read = unsafe {
            kite_matrix_client_mark_room_read(ptr::null_mut(), room_id.as_ptr(), event_id.as_ptr())
        };
        let members = unsafe { kite_matrix_client_room_members(ptr::null_mut(), room_id.as_ptr()) };
        let user_id = CString::new("@bob:kite.test").unwrap();
        let invite_member = unsafe {
            kite_matrix_client_invite_room_member(
                ptr::null_mut(),
                room_id.as_ptr(),
                user_id.as_ptr(),
            )
        };
        let permissions = unsafe {
            kite_matrix_client_room_member_permissions(
                ptr::null_mut(),
                room_id.as_ptr(),
                user_id.as_ptr(),
                user_id.as_ptr(),
            )
        };
        let action = CString::new("kick").unwrap();
        let moderate = unsafe {
            kite_matrix_client_moderate_room_member(
                ptr::null_mut(),
                room_id.as_ptr(),
                user_id.as_ptr(),
                action.as_ptr(),
                0,
                ptr::null(),
            )
        };
        let manage_action = CString::new("leave").unwrap();
        let manage = unsafe {
            kite_matrix_client_manage_room(
                ptr::null_mut(),
                room_id.as_ptr(),
                manage_action.as_ptr(),
                ptr::null(),
                ptr::null(),
            )
        };
        let settings_action = CString::new("get").unwrap();
        let room_settings = unsafe {
            kite_matrix_client_room_settings(
                ptr::null_mut(),
                room_id.as_ptr(),
                settings_action.as_ptr(),
                ptr::null(),
            )
        };
        let media_type = CString::new("image/png").unwrap();
        let media_bytes = [1_u8, 2, 3];
        let media_upload = unsafe {
            kite_matrix_client_upload_media(
                ptr::null_mut(),
                media_type.as_ptr(),
                media_bytes.as_ptr(),
                media_bytes.len() as u64,
            )
        };
        let media_uri = CString::new("mxc://kite.test/avatar").unwrap();
        let media_download = unsafe {
            kite_matrix_client_download_media(ptr::null_mut(), media_uri.as_ptr(), 384, 384)
        };
        let pagination =
            unsafe { kite_matrix_client_paginate_backwards(ptr::null_mut(), room_id.as_ptr()) };
        for result in [
            login,
            logout,
            send,
            favourite,
            create,
            read,
            invite_member,
            permissions,
            moderate,
            manage,
            room_settings,
            media_upload,
            media_download,
        ] {
            assert!(!result.is_null());
            let decoded = unsafe { CStr::from_ptr(result) }.to_str().unwrap();
            assert!(decoded.contains("\"ok\":false"));
            unsafe { kite_matrix_string_free(result) };
        }
        assert!(sync.is_null());
        assert!(members.is_null());
        assert!(pagination.is_null());
    }

    #[test]
    fn auth_session_primitives_return_safe_envelopes() {
        let discovery = unsafe { kite_matrix_discover_authentication(ptr::null()) };
        assert!(!discovery.is_null());
        let discovery_json = unsafe { CStr::from_ptr(discovery) }.to_str().unwrap();
        assert!(discovery_json.contains("\"code\":\"invalid_homeserver\""));
        unsafe { kite_matrix_string_free(discovery) };

        let homeserver = CString::new("http://localhost:8008").unwrap();
        let store = temporary_store();
        let store_text = CString::new(store.to_string_lossy().as_bytes()).unwrap();
        let passphrase = CString::new("deterministic-test-store-secret").unwrap();
        let client = unsafe {
            kite_matrix_client_new(
                homeserver.as_ptr(),
                store_text.as_ptr(),
                passphrase.as_ptr(),
            )
        };
        assert!(!client.is_null());

        let restored = unsafe { kite_matrix_client_restore_session(client) };
        assert!(!restored.is_null());
        let restored_json = unsafe { CStr::from_ptr(restored) }.to_str().unwrap();
        assert_eq!(restored_json, r#"{"ok":true,"value":null}"#);
        unsafe { kite_matrix_string_free(restored) };

        let persisted = unsafe { kite_matrix_client_persist_session(client) };
        assert!(!persisted.is_null());
        let persisted_json = unsafe { CStr::from_ptr(persisted) }.to_str().unwrap();
        assert!(persisted_json.contains("\"code\":\"session_unavailable\""));
        unsafe { kite_matrix_string_free(persisted) };

        unsafe { kite_matrix_client_free(client) };
        fs::remove_dir_all(store).unwrap();
    }

    #[test]
    fn returned_json_strings_have_an_explicit_free_boundary() {
        let value = json!({"cursor": "s1", "rooms": []});
        let encoded = json_to_c_string(&value);
        assert!(!encoded.is_null());
        let decoded = unsafe { CStr::from_ptr(encoded) }.to_str().unwrap();
        assert_eq!(decoded, r#"{"cursor":"s1","rooms":[]}"#);
        unsafe { kite_matrix_string_free(encoded) };
    }
}
