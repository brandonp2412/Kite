use std::ffi::{CStr, c_char};
use std::path::Path;
use std::ptr;

use matrix_sdk::Client;
use tokio::runtime::{Builder, Runtime};

const KITE_MATRIX_ABI_VERSION: u32 = 2;

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

    Box::into_raw(Box::new(KiteMatrixClient {
        client: Some(client),
        runtime,
    }))
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
        assert_eq!(kite_matrix_abi_version(), 2);
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
}
