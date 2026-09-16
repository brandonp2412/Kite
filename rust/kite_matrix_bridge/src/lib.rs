use std::collections::{HashMap, HashSet};
use std::ffi::{CStr, CString, c_char};
use std::path::Path;
use std::ptr;
use std::time::Duration;

use matrix_sdk::{
    Client, Error as MatrixError, HttpError, RoomMemberships,
    authentication::matrix::MatrixSession,
    config::SyncSettings,
    room::MessagesOptions,
    ruma::{
        OwnedTransactionId, RoomId, UInt, UserId,
        api::{
            client::{
                filter::{FilterDefinition, RoomEventFilter, RoomFilter},
                session::get_login_types::v3::LoginType,
            },
            error::ErrorKind,
        },
        events::room::{message::RoomMessageEventContent, power_levels::UserPowerLevel},
    },
};
use serde_json::{Value, json};
use tokio::runtime::{Builder, Runtime};

const KITE_MATRIX_ABI_VERSION: u32 = 10;
const KITE_MATRIX_SESSION_STORE_KEY: &[u8] = b"kite.matrix.session.v1";

pub struct KiteMatrixClient {
    client: Option<Client>,
    runtime: Runtime,
    backwards_pagination_tokens: HashMap<String, String>,
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
    let display_names = runtime.block_on(async {
        let mut display_names = HashMap::new();
        for sender in senders {
            let Ok(user_id) = UserId::parse(sender.as_str()) else {
                continue;
            };
            let display_name = room
                .get_member_no_sync(&user_id)
                .await
                .ok()
                .flatten()
                .and_then(|member| member.display_name().map(str::to_owned))
                .filter(|display_name| !display_name.trim().is_empty());
            if let Some(display_name) = display_name {
                display_names.insert(sender, display_name);
            }
        }
        display_names
    });
    for event in &mut events {
        let Some(sender) = event
            .get("sender")
            .and_then(Value::as_str)
            .map(str::to_owned)
        else {
            continue;
        };
        let Some(display_name) = display_names.get(&sender) else {
            continue;
        };
        if let Some(event) = event.as_object_mut() {
            event.insert(
                "sender_display_name".to_owned(),
                Value::String(display_name.clone()),
            );
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
            .server_name_or_homeserver_url(homeserver)
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
    ok_json(session_json(&session, matrix_client.homeserver().as_str()))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_send_text(
    client: *mut KiteMatrixClient,
    room_id: *const c_char,
    transaction_id: *const c_char,
    body: *const c_char,
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
    if room_id.is_empty() || transaction_id.is_empty() || body.is_empty() {
        return error_json("invalid_message", "The Matrix message is invalid.");
    }
    let Ok(room_id) = RoomId::parse(room_id) else {
        return error_json("invalid_room", "The Matrix room is invalid.");
    };

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
    let Ok(response) = client.runtime.block_on(async {
        room.send(RoomMessageEventContent::text_plain(body))
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

    let rooms = response
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
            let is_favourite = room.as_ref().is_some_and(|room| room.is_favourite());
            json!({
                "roomId": room_id.as_str(),
                "displayName": display_name,
                "unreadCount": unread_count,
                "highlightCount": highlight_count,
                "isFavourite": is_favourite,
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

    json_to_c_string(&json!({
        "cursor": response.next_batch,
        "rooms": rooms,
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
    options.limit = UInt::from(100_u8);
    let previous_access_token = matrix_client
        .matrix_auth()
        .session()
        .map(|session| session.tokens.access_token);
    let messages = match client.runtime.block_on(room.messages(options)) {
        Ok(messages) => messages,
        Err(error) => {
            return json_to_c_string(&json!({
                "error": format!("pagination failed: {error}"),
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

    fn temporary_store() -> std::path::PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!("kite-matrix-{}-{nonce}", std::process::id()))
    }

    #[test]
    fn abi_version_is_pinned() {
        assert_eq!(kite_matrix_abi_version(), 10);
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
            )
        };
        let sync = unsafe { kite_matrix_client_sync_once(ptr::null_mut(), 0, ptr::null(), 20) };
        let favourite =
            unsafe { kite_matrix_client_set_room_favourite(ptr::null_mut(), room_id.as_ptr(), 1) };
        let members = unsafe { kite_matrix_client_room_members(ptr::null_mut(), room_id.as_ptr()) };
        let pagination =
            unsafe { kite_matrix_client_paginate_backwards(ptr::null_mut(), room_id.as_ptr()) };
        for result in [login, logout, send, favourite] {
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
