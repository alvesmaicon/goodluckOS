// libgssapi_krb5.so.2 stub: libmono-native links it for Negotiate auth, which Stardew never uses.
// Every call fails with GSS_S_FAILURE; the real library would pull in krb5 and libcrypto.
#define FAIL(name) unsigned name(void) { return 13u << 16; }

void *GSS_C_NT_HOSTBASED_SERVICE, *GSS_C_NT_USER_NAME, *gss_mech_krb5;

FAIL(gss_accept_sec_context)
FAIL(gss_acquire_cred)
FAIL(gss_acquire_cred_with_password)
FAIL(gss_delete_sec_context)
FAIL(gss_display_name)
FAIL(gss_display_status)
FAIL(gss_import_name)
FAIL(gss_indicate_mechs)
FAIL(gss_init_sec_context)
FAIL(gss_inquire_context)
FAIL(gss_oid_equal)
FAIL(gss_release_buffer)
FAIL(gss_release_cred)
FAIL(gss_release_name)
FAIL(gss_release_oid_set)
FAIL(gss_unwrap)
FAIL(gss_wrap)
