# OAuth Setup for gradle-play-publisher

Since you cannot use a service account, gradle-play-publisher can authenticate via **OAuth 2.0** instead. 

## How OAuth Works

1. First time you run `publishReleaseBundle`, gradle-play-publisher opens your browser
2. You sign in with your **Google Play Developer account**
3. Grant gradle-play-publisher permission to access Play Console
4. Token is saved locally (~/.gradle/ directory)
5. Future uploads use the cached token — no re-authentication needed

## Step 1: Authenticate (One Time)

Run this in an **interactive terminal** (not in an IDE):

```bash
cd /Users/codybontecou/projects/health-md-android

# Run the publish command — a browser will open automatically
./gradlew publishReleaseBundle
```

When the browser opens:
1. Sign in with your **Google Play Developer account email**
2. Click **Allow** to grant gradle-play-publisher permission
3. Browser will close and upload continues automatically

## Step 2: Verify Success

After successful upload, you should see:
```
> Task :app:publishReleaseBundle
> Task :commitEditForComDotHealthmdDotAndroid

BUILD SUCCESSFUL in 45s
```

Then check Play Console:
- Go to [play.google.com/console](https://play.google.com/console)
- Select your app (HealthMD)
- Go to **Testing** → **Internal testing**
- You should see a new build uploaded

## Step 3: Future Uploads

Token is cached automatically. Just run:
```bash
./gradlew publishReleaseBundle          # Upload to internal testing (default)
./gradlew publishReleaseBundle --play-track=beta          # Upload to beta
./gradlew publishReleaseBundle --play-track=production    # Upload to production
```

## Token Location

OAuth token is stored in: `~/.gradle/play-console-oauth-*`
- Automatically managed by gradle-play-publisher
- Never commit to git
- Safe to delete (will re-authenticate on next upload)

## Revoke Access

If needed, you can revoke gradle-play-publisher's access:
1. Go to [myaccount.google.com/permissions](https://myaccount.google.com/permissions)
2. Find and click on "gradle-play-publisher"
3. Click "Remove access"
4. Next upload will re-prompt for authentication

## For CI/CD (GitHub Actions, etc.)

OAuth doesn't work in CI/CD because it needs browser interaction. Options:

1. **Manual approval workflow**: CI builds the bundle, you manually run `./gradlew publishReleaseBundle` locally
2. **Scheduled uploads**: CI prepares release, you trigger upload manually
3. **API token in secrets**: (Requires different setup)

For now, authenticate locally to test the workflow.

## Troubleshooting

**"No credentials specified" error**
- Make sure you're running in an **interactive terminal** (not piped/in IDE console)
- Try: `./gradlew publishReleaseBundle --info` for more details

**Browser doesn't open**
- Firewall or proxy issue
- Try setting: `export BROWSER=/path/to/browser` (e.g., `export BROWSER=/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome`)

**"Invalid authorization" after authentication**
- Token may be expired
- Delete `~/.gradle/play-console-oauth-*` and re-authenticate

## Next Steps

1. **Authenticate now** by running in interactive terminal:
   ```bash
   ./gradlew publishReleaseBundle
   ```

2. **Verify in Play Console** that build uploaded to internal testing

3. **Once working**, you can set up CI/CD uploads later

---

**Read also:**
- GRADLE_PLAY_PUBLISHER_SETUP.md — Overview of gradle-play-publisher
- PLAY_STORE_COMMANDS.md — Command reference
