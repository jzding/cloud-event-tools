# Cloud Event Proxy Security Tests

This directory contains security testing scripts for the cloud-event-proxy authentication system.

## Overview

The cloud-event-proxy implements dual authentication (mTLS + OAuth) for secure communication between PTP event publishers and consumers in OpenShift environments. These tests validate that the security mechanisms work correctly and cannot be bypassed.

## Authentication Architecture

The cloud-event-proxy enforces **dual authentication**:

1. **mTLS (Mutual TLS)**: Client certificate validation against OpenShift Service CA
2. **OAuth**: Bearer token validation against OpenShift OAuth server

Both authentication methods must be present and valid for destructive operations (POST, DELETE).

## Test Scripts

### `auth-test-script.sh`

Comprehensive authentication test that validates:

- ❌ **Rejection Cases** (should fail with 401 Unauthorized):
  1. No authentication (no certificate, no token)
  2. mTLS only (valid certificate, no OAuth token)  
  3. Invalid OAuth token (valid certificate, invalid token)

- ✅ **Success Case** (should succeed with 204 No Content):
  4. Full authentication (valid certificate + valid OAuth token)

#### Usage

The script must be run from within a consumer pod that has proper certificates mounted:

```bash
# Copy script to consumer pod and run
oc -n cloud-events cp auth-test-script.sh cloud-consumer-deployment:/tmp/
oc -n cloud-events exec -it deployment/cloud-consumer-deployment -- bash /tmp/auth-test-script.sh

# Or run directly via stdin
oc -n cloud-events exec -it deployment/cloud-consumer-deployment -- bash < auth-test-script.sh
```

#### Prerequisites

- Consumer pod deployed with proper mTLS certificates
- ServiceAccount token available at `/var/run/secrets/kubernetes.io/serviceaccount/token`
- Network access to `ptp-event-publisher-service-*` in `openshift-ptp` namespace
- At least one existing subscription or ability to create one

#### Expected Output

```
🔒 Cloud Event Proxy DELETE Subscription Authentication Test
============================================================

✅ Test 1: No authentication → REJECTED (401 - Client certificate required)
✅ Test 2: mTLS only → REJECTED (401 - Authorization header required)
✅ Test 3: Invalid OAuth token → REJECTED (401 - Invalid OAuth token)
✅ Test 4: Full authentication → ACCEPTED (204 - Successfully deleted)

🔒 SECURITY CONCLUSION
======================
The cloud-event-proxy server correctly enforces DUAL AUTHENTICATION
```

## Security Guarantees Tested

### ✅ Verified Security Features

1. **No Authentication Bypass**: All unauthorized requests properly rejected
2. **Certificate Validation**: Invalid/self-signed certificates rejected at TLS level
3. **OAuth Token Validation**: Malformed or invalid tokens rejected with clear errors
4. **Dual Authentication Enforcement**: Both mTLS AND OAuth required for destructive operations
5. **Proper HTTP Status Codes**: Consistent `401 Unauthorized` for auth failures, `204 No Content` for success
6. **Information Security**: Error messages are clear but don't expose internal details

### 🛡️ Attack Vectors Mitigated

- **Unauthenticated Access**: Cannot perform operations without proper credentials
- **Certificate Bypass**: Cannot use self-signed or invalid certificates
- **Token Replay**: Invalid or expired tokens are rejected
- **Single-Factor Authentication**: Both certificate AND token required

## Related Documentation

- [Cloud Event Proxy Authentication](https://github.com/redhat-cne/cloud-event-proxy/blob/main/AUTHENTICATION_IMPLEMENTATION.md)
- [REST API Authentication](https://github.com/redhat-cne/rest-api/blob/main/AUTHENTICATION.md)
- [OpenShift OAuth Integration](https://github.com/redhat-cne/rest-api/blob/main/OPENSHIFT_AUTHENTICATION.md)

## Contributing

When adding new security tests:

1. Follow the same pattern of testing both success and failure cases
2. Include clear documentation of expected results
3. Verify that security failures return appropriate HTTP status codes
4. Test edge cases and potential bypass attempts
5. Update this README with new test descriptions

## Security Contact

For security issues or questions about these tests, please contact the maintainers through the appropriate security channels.
