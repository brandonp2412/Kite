use std::ffi::{CStr, c_char};
use std::ptr;

use matrix_sdk::Client;
use tokio::runtime::{Builder, Runtime};

const KITE_MATRIX_ABI_VERSION: u32 = 1;

/// Opaque owner for the audited Matrix Rust SDK client and its runtime.
///
/// Dart must never dereference this type. Future C ABI functions accept the
/// pointer only as an opaque handle, keeping Matrix protocol and cryptographic
/// types on the Rust side of the boundary.
pub struct KiteMatrixClient {
    _client: Client,
    _runtime: Runtime,
}

#[unsafe(no_mangle)]
pub extern "C" fn kite_matrix_abi_version() -> u32 {
    KITE_MATRIX_ABI_VERSION
}

/// Build a Matrix Rust SDK client for an explicit homeserver URL.
///
/// Returns null when the pointer/string is invalid, the Tokio runtime cannot be
/// created, or Matrix SDK client construction fails. This function is blocking
/// by design and must only be called from a worker isolate on the Dart side.
///
/// # Safety
///
/// `homeserver` must point to a valid NUL-terminated C string for the duration
/// of this call. The returned pointer must be released exactly once with
/// [`kite_matrix_client_free`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_new(
    homeserver: *const c_char,
) -> *mut KiteMatrixClient {
    if homeserver.is_null() {
        return ptr::null_mut();
    }

    // SAFETY: The caller contract requires a valid NUL-terminated C string.
    let homeserver = unsafe { CStr::from_ptr(homeserver) };
    let Ok(homeserver) = homeserver.to_str() else {
        return ptr::null_mut();
    };

    let Ok(runtime) = Builder::new_multi_thread().enable_all().build() else {
        return ptr::null_mut();
    };
    let Ok(client) = runtime.block_on(Client::builder().homeserver_url(homeserver).build()) else {
        return ptr::null_mut();
    };

    Box::into_raw(Box::new(KiteMatrixClient {
        _client: client,
        _runtime: runtime,
    }))
}

/// Release a handle returned by [`kite_matrix_client_new`].
///
/// # Safety
///
/// `client` must be null or a pointer returned by `kite_matrix_client_new` that
/// has not already been freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn kite_matrix_client_free(client: *mut KiteMatrixClient) {
    if client.is_null() {
        return;
    }

    // SAFETY: The caller contract guarantees ownership of a live boxed handle.
    drop(unsafe { Box::from_raw(client) });
}

#[cfg(test)]
mod tests {
    use std::ffi::CString;

    use super::*;

    #[test]
    fn abi_version_is_pinned() {
        assert_eq!(kite_matrix_abi_version(), 1);
    }

    #[test]
    fn constructs_and_releases_matrix_sdk_client() {
        let homeserver = CString::new("http://localhost:8008").unwrap();
        // SAFETY: CString provides a valid NUL-terminated pointer for the call.
        let client = unsafe { kite_matrix_client_new(homeserver.as_ptr()) };
        assert!(!client.is_null());

        // SAFETY: `client` is the unique live handle returned directly above.
        unsafe { kite_matrix_client_free(client) };
    }

    #[test]
    fn rejects_invalid_pointer() {
        // SAFETY: Null is explicitly supported by the FFI contract.
        let client = unsafe { kite_matrix_client_new(ptr::null()) };
        assert!(client.is_null());
    }
}
