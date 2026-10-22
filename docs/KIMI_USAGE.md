# Kimi usage sources

Verified on 2026-10-22 using the existing local Kimi Code and Kimi desktop credentials. Tokens, user IDs, and subscription IDs are omitted. The Code token was expired and was refreshed through the existing OAuth flow, updating only its existing credential file. Desktop credentials were read without modification.

## Code quotas

`GET https://api.kimi.com/coding/v1/usages` returned HTTP 200 with:

```json
{
  "usage": {
    "limit": "100",
    "remaining": "100",
    "resetTime": "2026-10-22T15:51:00.685263Z"
  },
  "limits": [{
    "window": {"duration": 300, "timeUnit": "TIME_UNIT_MINUTE"},
    "detail": {
      "limit": "100",
      "remaining": "100",
      "resetTime": "2026-10-22T14:51:00.685263Z"
    }
  }],
  "usages": {
    "limit_5h": {"used_ratio": 0, "reset_time": "2026-10-22T14:51:00Z"},
    "limit_7d": {"used_ratio": 0.0001, "reset_time": "2026-10-22T15:50:59Z"}
  }
}
```

This response contained no plan-wide total. The fractional pools take precedence over the integer quota rows: `0.0001` means **0.01% used**, despite the legacy weekly row reporting 100 remaining. Stable IDs remain `kimi-300` and `kimi-weekly`.

The configured `https://api.kimi.ai/coding/v1/usages` returned HTTP 403, Cloudflare error 1010 (`browser_signature_banned`) to the Python investigation client. The response requested no further retries; investigation continued on the other user-requested Kimi endpoints. UsageDock continues to honor the configured Code base URL; no cross-region fallback or credential-file configuration change was added.

## Plan-wide total

Inspection of `/Applications/Kimi.app/Contents/Resources/app.asar`, `out/main/index.js`, found the desktop membership client calling:

`POST https://www.kimi.com/apiv2/kimi.gateway.membership.v2.MembershipService/GetSubscription`

The desktop's credit usage helpers read `balances[].amountUsedRatio` and `balances[].expireTime`. The existing desktop access token comes from `credentials.kimiWeb.accessToken` in its default `daimon-share/daimon/config.json`.

Calling this endpoint with the Code OAuth token returned HTTP 401. Calling it with the matching desktop token, JSON body `{}`, and `Connect-Protocol-Version: 1` returned HTTP 200. The relevant response projection was:

```json
{
  "balances": [{
    "feature": "FEATURE_OMNI",
    "type": "SUBSCRIPTION",
    "unit": "UNIT_CREDIT",
    "amountUsedRatio": 0.029,
    "expireTime": "2026-11-07T15:51:00.685263Z"
  }]
}
```

The live reading was **2.90% used / 97.10% remaining**, slightly above the user's earlier 2.89% observation. Its reset is **2026-11-08 00:51 JST**, matching the subscription page. The Code token's `sub` and `user_id`, the desktop token's `sub`, and desktop config's `userId` all matched; no identity values were logged.

The desktop also references `GetSubscriptionStats`. The Code token received HTTP 401 there. The corresponding path on `api.kimi.com` returned HTTP 404. Neither is needed to obtain the verified total.

## Adapter behavior and limits

- `kimi-total` is a separate ratio bucket named **Total** / **合計使用量**, with the balance expiry as its reset.
- Total requires exactly one `FEATURE_OMNI`, `UNIT_CREDIT`, `SUBSCRIPTION` balance with a valid fractional ratio and reset. Missing or ambiguous balances do not become 0% usage.
- The desktop and Code JWT subjects must match, and the desktop token must be unexpired. This check prevents mixing a desktop user's total with another CLI profile's quotas; the membership server still validates the token.
- The verified default desktop config path is supported. A missing, expired, or different-account desktop session leaves Code quotas visible with a notice. A Code API failure can leave a valid total visible with a notice. Both sources failing fails the refresh.
- Desktop secrets stay in the existing desktop config. UsageDock does not persist them, print them, or rotate the desktop session. Opening Kimi and signing in again is the recovery path.
- With no account override and a global Auto source, Kimi's Percent and Outer use Total when available. Explicit account/global quota choices remain effective. Inner and Timer retain their existing settings.

## Verification

`xcodebuild -project UsageDock.xcodeproj -scheme UsageDock -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData test CODE_SIGNING_ALLOWED=NO` passed: **132 tests, 0 failures**.

Tests cover fractional Code pools taking precedence, the count-only fallback, total/reset decoding, malformed or ambiguous totals, matching and expired desktop credentials, separate endpoint tokens, each partial failure, both APIs failing, default rail selection, explicit overrides, and Japanese localization. Network tests use synthetic credentials and an injected URL protocol; the live API observations above were made separately. An interactive run of the updated app against the user's account was not performed.
