use std::ffi::{CStr, CString, c_char};
use std::path::Path;
use std::ptr;
use std::time::Duration;

use matrix_sdk::{
    Client,
    authentication::matrix::MatrixSession,
    config::SyncSettings,
    ruma::{
        OwnedTransactionId, RoomId, UInt,
        api::client::filter::{FilterDefinition, RoomEventFilter, RoomFilter},
        events::room::message::RoomMessageEventContent,
    },
};
use serde_json::{Value, json};
use tokio::runtime::{Builder, Runtime};

const KITE_MATRIX_ABI_VERSION: u32 = 6;
const KITE_MATRIX_SESSION_STORE_KEY: &[u8] = b"kite.matrix.session.v1";

pub struct KiteMatrixClient {
    client: Option<Client>,
    runtime: Runtime,
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

fn timeline_events_json<'a>(
    events: impl IntoIterator<Item = &'a matrix_sdk::deserialized_responses::TimelineEvent>,
) -> Vec<Value> {
    events
        .into_iter()
        .filter_map(|event| serde_json::from_str(event.raw().json().get()).ok())
        .collect()
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
    }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_login_password(
    client: *mut KiteMatrixClient,
    username: *const c_char,
    password: *const c_char,
) -> *mut c_char {
    if client.is_null() {
        return ptr::null_mut();
    }
    let Some(username) = (unsafe { required_utf8(username) }) else {
        return ptr::null_mut();
    };
    let Some(password) = (unsafe { required_utf8(password) }) else {
        return ptr::null_mut();
    };
    if username.is_empty() || password.is_empty() {
        return ptr::null_mut();
    }

    let client = unsafe { &mut *client };
    let Some(matrix_client) = client.client.as_ref() else {
        return ptr::null_mut();
    };
    let Ok(response) = client.runtime.block_on(
        matrix_client
            .matrix_auth()
            .login_username(username, password)
            .initial_device_display_name("Kite")
            .send(),
    ) else {
        return ptr::null_mut();
    };
    let session = MatrixSession::from(&response);
    let Ok(session_bytes) = serde_json::to_vec(&session) else {
        return ptr::null_mut();
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
        return ptr::null_mut();
    }

    json_to_c_string(&json!({
        "userId": response.user_id.as_str(),
        "deviceId": response.device_id.as_str(),
    }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_send_text(
    client: *mut KiteMatrixClient,
    room_id: *const c_char,
    transaction_id: *const c_char,
    body: *const c_char,
) -> *mut c_char {
    if client.is_null() {
        return ptr::null_mut();
    }
    let Some(room_id) = (unsafe { required_utf8(room_id) }) else {
        return ptr::null_mut();
    };
    let Some(transaction_id) = (unsafe { required_utf8(transaction_id) }) else {
        return ptr::null_mut();
    };
    let Some(body) = (unsafe { required_utf8(body) }) else {
        return ptr::null_mut();
    };
    if room_id.is_empty() || transaction_id.is_empty() || body.is_empty() {
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
    let Ok(response) = client.runtime.block_on(async {
        room.send(RoomMessageEventContent::text_plain(body))
            .with_transaction_id(OwnedTransactionId::from(transaction_id))
            .await
    }) else {
        return ptr::null_mut();
    };

    json_to_c_string(&json!({
        "eventId": response.response.event_id.as_str(),
    }))
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
    let Ok(response) = client.runtime.block_on(matrix_client.sync_once(settings)) else {
        return ptr::null_mut();
    };

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
            json!({
                "roomId": room_id.as_str(),
                "displayName": display_name,
                "unreadCount": unread_count,
                "latestEventTimestamp": latest_event_timestamp,
                "latestEventId": latest_event_id,
                "prevBatch": update.timeline.prev_batch,
                "events": timeline_events_json(update.timeline.events.iter()),
            })
        })
        .collect::<Vec<_>>();

    json_to_c_string(&json!({
        "cursor": response.next_batch,
        "rooms": rooms,
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
    let Ok((event_cache, _drop_handles)) = client.runtime.block_on(room.event_cache()) else {
        return ptr::null_mut();
    };
    let Ok(outcome) = client
        .runtime
        .block_on(event_cache.pagination().run_backwards_once(20))
    else {
        return ptr::null_mut();
    };

    json_to_c_string(&json!({
        "roomId": room_id.as_str(),
        "reachedStart": outcome.reached_start,
        "events": timeline_events_json(outcome.events.iter()),
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
        assert_eq!(kite_matrix_abi_version(), 6);
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
        let pagination =
            unsafe { kite_matrix_client_paginate_backwards(ptr::null_mut(), room_id.as_ptr()) };
        assert!(login.is_null());
        assert!(send.is_null());
        assert!(sync.is_null());
        assert!(pagination.is_null());
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
