# planka-cli

A single-file Bash CLI for the [Planka](https://planka.app) project management board. Designed for scripting, CI/CD pipelines, and AI agent workflows.

## Features

- **Single file, no installation** — just `bash`, `curl`, and `python3`
- **Human and machine output** — TSV for quick inspection, JSON for piping to `jq`
- **Label support** — list, attach, and filter by labels
- **Board-scoped** — all commands operate against a single configured board

## Requirements

- Bash 4+
- curl
- Python 3 (used for JSON parsing — no pip dependencies)

## Setup

1. Clone the repo:

```bash
git clone git@github.com:roelven/planka-cli.git
cd planka-cli
```

2. Create a `config.env` file in the same directory as `planka.sh`:

```bash
PLANKA_URL=https://planka.example.com
PLANKA_TOKEN=your-api-token-here
PLANKA_BOARD_ID=your-board-id
```

3. Make it executable:

```bash
chmod +x planka.sh
```

> **Never commit `config.env`.** Add it to your `.gitignore`.

### Getting your API token

Log in to your Planka instance, then grab the token from your browser's developer tools (Application > Cookies > `accessToken`), or use the login API:

```bash
curl -s -X POST https://planka.example.com/api/access-tokens \
  -H "Content-Type: application/json" \
  -d '{"emailOrUsername":"you@example.com","password":"..."}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['item'])"
```

### Getting your board ID

```bash
./planka.sh lists
```

If you only have one board, the default will work. Otherwise, set `PLANKA_BOARD_ID` in `config.env`. You can find board IDs in the Planka URL when viewing a board (`/boards/<id>`).

## Usage

### Board structure

```bash
# List all columns (lists) on the board
./planka.sh lists
```

Output (TSV):
```
1722607259374061405  Todo
1722607333906843486  In Progress
1722607340785502047  Done
```

### Cards

```bash
# List all cards (TSV: id, list_id, name)
./planka.sh cards

# Filter by list
./planka.sh cards <list_id>

# Get full card details (JSON)
./planka.sh card <card_id>

# List cards as JSON with labels (for scripting)
./planka.sh list-cards <list_id>
```

`list-cards` returns structured JSON — ideal for piping to `jq`:

```json
[
  {
    "id": "1722730658196883349",
    "name": "Fix token expiry",
    "description": "Tokens should expire after 5 hours",
    "position": 57343.125,
    "labels": ["BUG"]
  }
]
```

Example — find the first card labeled `impl` in your Todo column:

```bash
./planka.sh list-cards "$TODO_LIST_ID" \
  | jq -r '[.[] | select(.labels[] == "impl")] | first | .id'
```

### Creating cards

```bash
# Basic
./planka.sh create <list_id> "Card title"

# With description
./planka.sh create <list_id> "Card title" "Some description"

# With label (attached in one call)
./planka.sh create <list_id> "Card title" "Description" --label impl

# Label without description
./planka.sh create <list_id> "Card title" --label impl
```

### Moving cards

```bash
./planka.sh move <card_id> <list_id>
```

### Updating cards

```bash
# Update arbitrary fields
./planka.sh update <card_id> name="New title" description="New desc"

# Shorthand for description updates
./planka.sh update-description <card_id> "Full new description text"
```

### Comments

```bash
./planka.sh comment <card_id> "This is a comment"
```

### Labels

```bash
# List all labels on the board (TSV: id, name, color)
./planka.sh labels

# Add a label to a card (by name, case-insensitive)
./planka.sh label <card_id> BUG
./planka.sh label <card_id> impl
```

> Labels must be created in the Planka UI first. The CLI attaches existing labels to cards by name.

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `PLANKA_URL` | Yes | Base URL of your Planka instance (no trailing slash) |
| `PLANKA_TOKEN` | Yes | API bearer token |
| `PLANKA_BOARD_ID` | Yes | Board ID to operate on (find it in the Planka URL: `/boards/<id>`) |

Variables can be set in `config.env` (auto-loaded from the script's directory) or exported in your shell.

## Command reference

| Command | Arguments | Output | Description |
|---|---|---|---|
| `lists` | — | TSV | List board columns |
| `cards` | `[list_id]` | TSV | List cards, optionally filtered by column |
| `list-cards` | `<list_id>` | JSON | List cards with labels (for scripting) |
| `card` | `<card_id>` | JSON | Full card details |
| `create` | `<list_id> "title" ["desc"] [--label name]` | text | Create a card |
| `move` | `<card_id> <list_id>` | text | Move card to a column |
| `update` | `<card_id> field=value ...` | text | Update card fields |
| `update-description` | `<card_id> "description"` | text | Update card description |
| `comment` | `<card_id> "text"` | text | Add a comment |
| `labels` | — | TSV | List board labels |
| `label` | `<card_id> <label_name>` | text | Add a label to a card |

## Use with AI agents

This CLI was built as an interface between autonomous AI agents and a Planka board. A typical agent workflow:

```bash
# 1. Find the next task to work on
CARD=$(./planka.sh list-cards "$TODO_LIST" | jq -r 'first | .id')

# 2. Move it to In Progress
./planka.sh move "$CARD" "$IN_PROGRESS_LIST"

# 3. Write a plan back to the card
./planka.sh update-description "$CARD" "## Plan\n- [ ] Step 1\n- [ ] Step 2"

# 4. Do the work...

# 5. Move to Done
./planka.sh move "$CARD" "$DONE_LIST"
./planka.sh comment "$CARD" "Completed in commit abc123"
```

## License

MIT
