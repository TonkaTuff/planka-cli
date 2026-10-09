#!/usr/bin/env bash
# planka.sh — Planka API wrapper for the product agent
#
# Usage:
#   ./scripts/planka.sh lists                                          # List all lists on the board
#   ./scripts/planka.sh cards [list_id]                                # List cards (TSV: id, list_id, name)
#   ./scripts/planka.sh list-cards <list_id>                           # List cards as JSON (for pipeline parsing)
#   ./scripts/planka.sh card <card_id>                                 # Get card details
#   ./scripts/planka.sh create <list_id> "title" ["desc"] [--label x] # Create card (optionally label it)
#   ./scripts/planka.sh move <card_id> <list_id>                       # Move card to list
#   ./scripts/planka.sh update <card_id> field=value ...               # Update card (name=x, description=x)
#   ./scripts/planka.sh update-description <card_id> "new description" # Update card description
#   ./scripts/planka.sh comment <card_id> "text"                       # Add comment to card
#   ./scripts/planka.sh labels                                         # List board labels
#   ./scripts/planka.sh label <card_id> <label_name>                   # Add label to card (by name)
#
# Config: reads PLANKA_URL and PLANKA_TOKEN from environment or config.env

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/config.env" ]; then
    set -a
    source "$SCRIPT_DIR/config.env"
    set +a
fi

: "${PLANKA_URL:?Set PLANKA_URL in config.env}"
: "${PLANKA_TOKEN:?Set PLANKA_TOKEN in config.env}"
: "${PLANKA_BOARD_ID:?Set PLANKA_BOARD_ID in config.env}"

API="$PLANKA_URL/api"
AUTH="Authorization: Bearer $PLANKA_TOKEN"

_get()  { curl -sf -H "$AUTH" "$API/$1"; }
_post() { curl -sf -H "$AUTH" -H "Content-Type: application/json" -X POST -d "$2" "$API/$1"; }
_patch(){ curl -sf -H "$AUTH" -H "Content-Type: application/json" -X PATCH -d "$2" "$API/$1"; }

cmd="${1:-help}"
shift || true

case "$cmd" in
    lists)
        _get "boards/$PLANKA_BOARD_ID" | python3 -c "
import sys, json
data = json.load(sys.stdin)
lists = data.get('included', {}).get('lists', data.get('lists', []))
if isinstance(lists, list):
    for l in sorted((x for x in lists if x.get('position') is not None), key=lambda x: x['position']):
        print(f\"{l['id']}\t{l['name']}\")
elif isinstance(lists, dict):
    for lid, l in lists.items():
        print(f\"{lid}\t{l.get('name', '?')}\")
"
        ;;

    cards)
        list_id="${1:-}"
        _get "boards/$PLANKA_BOARD_ID" | python3 -c "
import sys, json
data = json.load(sys.stdin)
cards = data.get('included', {}).get('cards', data.get('cards', []))
list_filter = '$list_id'
if isinstance(cards, list):
    for c in cards:
        if not list_filter or c.get('listId') == list_filter:
            print(f\"{c['id']}\t{c.get('listId','?')}\t{c['name']}\")
elif isinstance(cards, dict):
    for cid, c in cards.items():
        if not list_filter or c.get('listId') == list_filter:
            print(f\"{cid}\t{c.get('listId','?')}\t{c.get('name','?')}\")
"
        ;;

    card)
        card_id="${1:?Usage: planka.sh card <card_id>}"
        _get "cards/$card_id" | python3 -m json.tool
        ;;

    create)
        list_id="${1:?Usage: planka.sh create <list_id> \"title\" [\"desc\"] [--label name]}"
        name="${2:?Usage: planka.sh create <list_id> \"title\" [\"desc\"] [--label name]}"
        shift 2
        desc=""
        label_name=""
        # Parse remaining args: optional description, then --label flag
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --label) label_name="${2:?--label requires a name}"; shift 2 ;;
                *) desc="$1"; shift ;;
            esac
        done
        payload=$(python3 -c "
import json, sys
name, desc = sys.argv[1], sys.argv[2]
d = {'name': name, 'position': 65535, 'type': 'project'}
if desc:
    d['description'] = desc
print(json.dumps(d))
" "$name" "$desc")
        result=$(_post "lists/$list_id/cards" "$payload")
        card_id=$(echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
item = data.get('item', data)
print(item.get('id', ''))
")
        echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
item = data.get('item', data)
print(f\"Created: {item.get('id', '?')} — {item.get('name', '?')}\")
"
        # If --label was given, attach it
        if [[ -n "$label_name" && -n "$card_id" ]]; then
            "$0" label "$card_id" "$label_name"
        fi
        ;;

    move)
        card_id="${1:?Usage: planka.sh move <card_id> <list_id>}"
        list_id="${2:?Usage: planka.sh move <card_id> <list_id>}"
        _patch "cards/$card_id" "{\"listId\":\"$list_id\",\"position\":65535}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
item = data.get('item', data)
print(f\"Moved: {item.get('id','?')} → list {item.get('listId','?')}\")
"
        ;;

    update)
        card_id="${1:?Usage: planka.sh update <card_id> field=value}"
        shift
        # Build JSON from field=value pairs
        payload=$(python3 -c "
import json, sys
fields = {}
for arg in sys.argv[1:]:
    k, v = arg.split('=', 1)
    fields[k] = v
print(json.dumps(fields))
" "$@")
        _patch "cards/$card_id" "$payload" | python3 -c "
import sys, json
data = json.load(sys.stdin)
item = data.get('item', data)
print(f\"Updated: {item.get('id','?')} — {item.get('name','?')}\")
"
        ;;

    comment)
        card_id="${1:?Usage: planka.sh comment <card_id> \"text\"}"
        text="${2:?Usage: planka.sh comment <card_id> \"text\"}"
        payload=$(python3 -c "import json, sys; print(json.dumps({'text': sys.argv[1]}))" "$text")
        _post "cards/$card_id/comments" "$payload" | python3 -c "
import sys, json
data = json.load(sys.stdin)
item = data.get('item', data)
print(f\"Comment added: {item.get('id', '?')}\")
"
        ;;

    update-description)
        card_id="${1:?Usage: planka.sh update-description <card_id> \"new description\"}"
        desc="${2:?Usage: planka.sh update-description <card_id> \"new description\"}"
        payload=$(python3 -c "import json, sys; print(json.dumps({'description': sys.argv[1]}))" "$desc")
        _patch "cards/$card_id" "$payload" | python3 -c "
import sys, json
data = json.load(sys.stdin)
item = data.get('item', data)
print(f\"Description updated: {item.get('id','?')} — {item.get('name','?')}\")
"
        ;;

    labels)
        _get "boards/$PLANKA_BOARD_ID" | python3 -c "
import sys, json
data = json.load(sys.stdin)
labels = data.get('included', {}).get('labels', data.get('labels', []))
if isinstance(labels, list):
    for l in labels:
        print(f\"{l['id']}\t{l.get('name', '?')}\t{l.get('color', '?')}\")
elif isinstance(labels, dict):
    for lid, l in labels.items():
        print(f\"{lid}\t{l.get('name', '?')}\t{l.get('color', '?')}\")
else:
    print('No labels found', file=sys.stderr)
"
        ;;

    label)
        card_id="${1:?Usage: planka.sh label <card_id> <label_name>}"
        label_name="${2:?Usage: planka.sh label <card_id> <label_name>}"
        # Look up label ID by name from board data
        label_id=$(_get "boards/$PLANKA_BOARD_ID" | python3 -c "
import sys, json
data = json.load(sys.stdin)
labels = data.get('included', {}).get('labels', data.get('labels', []))
target = sys.argv[1]
if isinstance(labels, list):
    for l in labels:
        if l.get('name', '').lower() == target.lower():
            print(l['id']); sys.exit(0)
elif isinstance(labels, dict):
    for lid, l in labels.items():
        if l.get('name', '').lower() == target.lower():
            print(lid); sys.exit(0)
" "$label_name") || true
        if [[ -z "$label_id" ]]; then
            echo "Error: label '$label_name' not found on board. Use 'planka.sh labels' to see available labels." >&2
            exit 1
        fi
        _post "cards/$card_id/card-labels" "{\"labelId\":\"$label_id\"}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
item = data.get('item', data)
print(f\"Label added: {item.get('id', '?')} → card $card_id\")
" || { echo "Error: failed to add label '$label_name' to card $card_id" >&2; exit 1; }
        ;;

    list-cards)
        list_id="${1:?Usage: planka.sh list-cards <list_id>}"
        _get "boards/$PLANKA_BOARD_ID" | python3 -c "
import sys, json
data = json.load(sys.stdin)
included = data.get('included', {})

# Parse cards
cards = included.get('cards', data.get('cards', []))
if isinstance(cards, dict):
    cards = [dict(v, id=k) for k, v in cards.items()]

# Parse labels (board-level)
board_labels = included.get('labels', data.get('labels', []))
if isinstance(board_labels, dict):
    board_labels = [dict(v, id=k) for k, v in board_labels.items()]
label_map = {l['id']: l.get('name', '?') for l in (board_labels if isinstance(board_labels, list) else [])}

# Parse card-label memberships
card_label_links = included.get('cardLabels', [])
if isinstance(card_label_links, dict):
    card_label_links = [dict(v, id=k) for k, v in card_label_links.items()]
# Build card_id → [label_name, ...]
card_labels = {}
for cl in (card_label_links if isinstance(card_label_links, list) else []):
    cid = cl.get('cardId', '')
    lid = cl.get('labelId', '')
    card_labels.setdefault(cid, []).append(label_map.get(lid, lid))

list_filter = sys.argv[1]
result = []
for c in (cards if isinstance(cards, list) else []):
    if c.get('listId') == list_filter:
        result.append({
            'id': c.get('id', ''),
            'name': c.get('name', ''),
            'description': c.get('description', ''),
            'position': c.get('position', 0),
            'labels': card_labels.get(c.get('id', ''), []),
        })
result.sort(key=lambda x: x.get('position', 0))
print(json.dumps(result, indent=2))
" "$list_id"
        ;;

    help|*)
        echo "Usage: planka.sh <command> [args]"
        echo ""
        echo "Commands:"
        echo "  lists                                          List board lists"
        echo "  cards [list_id]                                 List cards (TSV)"
        echo "  list-cards <list_id>                            List cards as JSON (id, name, labels)"
        echo "  card <card_id>                                  Get card details"
        echo "  create <list_id> \"title\" [\"desc\"] [--label x]  Create card"
        echo "  move <card_id> <list_id>                        Move card to list"
        echo "  update <card_id> field=value ...                Update card fields"
        echo "  update-description <card_id> \"desc\"             Update card description"
        echo "  comment <card_id> \"text\"                        Add comment"
        echo "  labels                                          List board labels"
        echo "  label <card_id> <label_name>                    Add label to card"
        ;;
esac
