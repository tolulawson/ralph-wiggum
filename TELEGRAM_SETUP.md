# Telegram Notifications Setup

This repo includes Telegram helper functions in `scripts/lib/notifications.sh`.
They can send progress updates via Telegram, but they are **not wired into the
unified `./scripts/ralph-loop.sh` by default**.

Use this guide if you want to integrate Telegram notifications into your own
wrapper script, custom hooks, or project-specific workflow around Ralph.

## Prerequisites

You'll need:
1. A Telegram account
2. A Telegram bot
3. A chat/channel to receive notifications

## Step 1: Create a Telegram Bot

1. Open Telegram and search for `@BotFather`
2. Send `/newbot` to BotFather
3. Follow the prompts to name your bot
4. BotFather will give you a **bot token** like: `123456789:ABCdefGHIjklMNOpqrSTUvwxYZ`
5. Save this token — you'll need it for `TG_BOT_TOKEN`

## Step 2: Get Your Chat ID

**Option A: Personal Chat**
1. Search for your bot in Telegram and start a conversation
2. Send any message to your bot
3. Visit: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
4. Look for `"chat":{"id":123456789}` — that number is your chat ID

**Option B: Group Chat**
1. Add your bot to a group
2. Send a message in the group
3. Visit: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
4. Look for `"chat":{"id":-123456789}` (group IDs are negative)

**Option C: Channel**
1. Create a channel in Telegram
2. Add your bot as an administrator
3. Post something to the channel
4. Visit: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
5. Look for the channel ID (usually starts with `-100`)

## Step 3: Set Environment Variables

Add these to your shell profile (`~/.bashrc`, `~/.zshrc`, etc.):

```bash
export TG_BOT_TOKEN="your-bot-token-here"
export TG_CHAT_ID="your-chat-id-here"
```

Or create a `.env` file in your project:

```bash
TG_BOT_TOKEN=your-bot-token-here
TG_CHAT_ID=your-chat-id-here
```

And source it before running any helper-powered workflow:

```bash
source .env
```

## Step 4: Test the Connection

Run this command to verify:

```bash
curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
  -d chat_id="${TG_CHAT_ID}" \
  -d text="🤖 Ralph Wiggum test message!"
```

You should receive the message in Telegram.

## Using The Helper Library

Source the helper library in your own script or shell session:

```bash
source ./scripts/lib/notifications.sh
check_telegram
```

### Send a Text Notification

```bash
source ./scripts/lib/notifications.sh
check_telegram
send_telegram "🤖 Ralph Wiggum test message!"
```

### Create a Completion Log Entry

```bash
source ./scripts/lib/notifications.sh
create_completion_log "example-spec" "Completed successfully." "graph TD; A[Start] --> B[Done]"
```

This writes markdown (and optionally a generated diagram image) into `completion_log/`.

## Audio Notifications (Optional)

For audio TTS notifications, you also need a **Chutes API key**.

[Chutes](https://chutes.ai) is an AI inference platform with excellent price/intelligence ratios. They offer text-to-speech via Kokoro TTS.

### Get a Chutes API Key

1. Visit [chutes.ai](https://chutes.ai)
2. Sign up for an account
3. Generate an API key from your dashboard
4. Set the environment variable:

```bash
export CHUTES_API_KEY="cpk_your-key-here"
```

### Enable Audio In Your Own Wrapper

The audio helper is controlled by the `TELEGRAM_AUDIO` shell variable in
`scripts/lib/notifications.sh`.

Example:

```bash
source ./scripts/lib/notifications.sh
check_telegram
TELEGRAM_AUDIO=true
send_telegram_audio "Ralph Wiggum progress update." "Progress Update"
```

You can call this from your own wrapper script after loop milestones.

### Voice Options

The audio uses Chutes Kokoro TTS with these voice options:
- American Female: af_sky, af_bella, af_sarah, af_nicole
- American Male: am_adam, am_michael (default)
- British Female: bf_emma, bf_isabella
- British Male: bm_george, bm_lewis

Edit the script to change voices.

## Disabling Notifications

Because the unified loop does not enable Telegram notifications automatically,
there is nothing to disable in the stock `./scripts/ralph-loop.sh` command.

If you are using your own wrapper and want to suppress messages for a run, avoid
sourcing the helper library, unset the environment variables, or set:

```bash
source ./scripts/lib/notifications.sh
TELEGRAM_ENABLED=false
TELEGRAM_AUDIO=false
```

## What Notifications Do You Get?

1. **Loop Start**: If your wrapper sends a start message
2. **Spec Completed**: If your workflow calls `send_telegram` after completion
3. **Consecutive Failures**: If your wrapper emits warnings after retries
4. **Stuck Specs**: If your workflow checks `NR_OF_TRIES`
5. **Loop Finished**: If your wrapper sends a closing summary

## Example Messages

```
🚀 Ralph Loop Started
Mode: build
Branch: main
Specs: 5
```

```
✅ Spec Completed: 003-user-auth
Iteration: 3
```

```
⚠️ Ralph Loop Warning: 3 consecutive failures on spec 004-dashboard
```

```
🏁 Ralph Loop Finished
Iterations: 12
Completed: 4 specs
```

## Troubleshooting

### "Bad Request: chat not found"
- Make sure you've sent at least one message to the bot/channel first
- Verify the chat ID is correct (check for negative sign on groups)

### "Unauthorized"
- Your bot token is invalid
- Regenerate it with BotFather

### Audio not working
- Verify your CHUTES_API_KEY is valid
- Check you have credits on your Chutes account
- Ensure your wrapper sets `TELEGRAM_AUDIO=true` before calling `send_telegram_audio`

## Security Notes

- Never commit your bot token or chat ID to version control
- Add `.env` to your `.gitignore`
- The bot token gives full control of your bot — keep it secret
