# License access

NiceVoice uses individual license codes for beta access.

## Product rule

- The app remains free for normal use.
- Beta features are unlocked by a per-user license code.
- Each license code can be activated once.
- X login is not required for the first beta entitlement flow.
- The app stores the successful entitlement in Keychain.

## App flow

1. The user opens `About` and enters a license code.
2. The app normalizes the code by trimming whitespace, removing inner whitespace, and uppercasing it.
3. The app creates or reuses a Keychain-stored device ID.
4. The app sends the normalized code, device ID, and app version to the license API.
5. The app stores the returned entitlement token in Keychain.
6. Beta features check the Keychain entitlement through `AuthManager.canUseBetaFeatures`.

## API configuration

Set `NICEVOICE_LICENSE_API_URL` when packaging the app. `Scripts/package-app.sh` writes it to `NiceVoiceLicenseAPIURL` in `Info.plist`.

## Activation endpoint

`POST /v1/licenses/activate`

Request:

```json
{
  "code": "NV-BETA-EXAMPLE",
  "deviceID": "6A42B13B-3F5C-45BD-81BF-15E89ED7C39B",
  "appVersion": "0.1.4"
}
```

Success response:

```json
{
  "betaAccess": true,
  "entitlementToken": "signed-token",
  "expiresAt": null
}
```

Rejected response:

```json
{
  "message": "このライセンスコードはすでに使用されています"
}
```

## Server rule

The server must store only a hash of each code. Activation must be a single atomic transition from `unused` to `used`.

Example SQL shape:

```sql
UPDATE license_codes
SET status = 'used',
    activated_device_id = ?,
    activated_at = CURRENT_TIMESTAMP
WHERE code_hash = ?
  AND status = 'unused';
```

If this update changes zero rows, the server must reject the request. This is what prevents a known code from being applied twice.
