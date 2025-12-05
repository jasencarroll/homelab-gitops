# Plane API Documentation

Complete API reference for the self-hosted Plane instance at `plane.lab.axiomlayer.com`.

## Table of Contents

- [Overview](#overview)
- [Authentication](#authentication)
- [Base URL](#base-url)
- [Response Format](#response-format)
- [Endpoints](#endpoints)
  - [User](#user)
  - [Workspace](#workspace)
  - [Projects](#projects)
  - [Work Items (Issues)](#work-items-issues)
  - [States](#states)
  - [Labels](#labels)
  - [Cycles (Sprints)](#cycles-sprints)
  - [Modules](#modules)
  - [Comments](#comments)
  - [Activities](#activities)
  - [Links](#links)
  - [Attachments](#attachments)
- [Data Reference](#data-reference)
- [Example Scripts](#example-scripts)
- [Troubleshooting](#troubleshooting)

---

## Overview

Plane is an open-source project management tool. This documentation covers the REST API for the self-hosted instance running in the homelab.

| Property | Value |
|----------|-------|
| Instance URL | https://plane.lab.axiomlayer.com |
| API Version | v1 |
| Auth Method | API Key |
| Workspace Slug | `axiomlayer` |

---

## Authentication

All API requests require authentication via the `x-api-key` header.

```bash
curl -H "x-api-key: $PLANE_API_KEY" \
  "https://plane.lab.axiomlayer.com/api/v1/users/me/"
```

### Getting an API Key

1. Log in to Plane at https://plane.lab.axiomlayer.com
2. Go to **Profile Settings** > **API Tokens**
3. Create a new API token
4. Store in `.env` as `PLANE_API_KEY`

---

## Base URL

```
https://plane.lab.axiomlayer.com/api/v1
```

All endpoints below are relative to this base URL.

---

## Response Format

### Paginated Responses

Most list endpoints return paginated responses:

```json
{
  "grouped_by": null,
  "sub_grouped_by": null,
  "total_count": 9,
  "next_cursor": "1000:1:0",
  "prev_cursor": "1000:-1:1",
  "next_page_results": false,
  "prev_page_results": false,
  "count": 9,
  "total_pages": 1,
  "total_results": 9,
  "extra_stats": null,
  "results": [...]
}
```

### Error Responses

```json
{
  "error": "Page not found."
}
```

### HTTP Status Codes

| Code | Meaning |
|------|---------|
| 200 | Success |
| 201 | Created |
| 204 | Deleted (no content) |
| 400 | Bad request |
| 401 | Unauthorized |
| 404 | Not found |
| 500 | Server error |

---

## Endpoints

### User

#### Get Current User

```http
GET /users/me/
```

**Response:**

```json
{
  "id": "<user-uuid>",
  "first_name": "First",
  "last_name": "Last",
  "email": "user@example.com",
  "avatar": "",
  "avatar_url": null,
  "display_name": "username"
}
```

---

### Workspace

#### List Workspace Members

```http
GET /workspaces/{workspace_slug}/members/
```

**Example:**

```bash
curl -H "x-api-key: $PLANE_API_KEY" \
  "https://plane.lab.axiomlayer.com/api/v1/workspaces/axiomlayer/members/"
```

**Response:**

```json
[
  {
    "id": "<user-uuid>",
    "first_name": "First",
    "last_name": "Last",
    "email": "user@example.com",
    "display_name": "username",
    "role": 20
  }
]
```

**Role Values:**

| Role | Value |
|------|-------|
| Guest | 5 |
| Viewer | 10 |
| Member | 15 |
| Admin | 20 |

---

### Projects

#### List Projects

```http
GET /workspaces/{workspace_slug}/projects/
```

**Example:**

```bash
curl -H "x-api-key: $PLANE_API_KEY" \
  "https://plane.lab.axiomlayer.com/api/v1/workspaces/axiomlayer/projects/"
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| id | uuid | Project ID |
| name | string | Project name |
| identifier | string | Short code (e.g., "HOME") |
| description | string | Project description |
| network | int | 0=Secret, 2=Public |
| total_members | int | Member count |
| total_cycles | int | Sprint count |
| total_modules | int | Module count |
| workspace | uuid | Workspace ID |

#### Example Response

Projects are returned with their UUIDs which are used in subsequent API calls.

---

### Work Items (Issues)

#### List Work Items

```http
GET /workspaces/{workspace_slug}/projects/{project_id}/work-items/
```

**Example:**

```bash
curl -H "x-api-key: $PLANE_API_KEY" \
  "https://plane.lab.axiomlayer.com/api/v1/workspaces/axiomlayer/projects/<project-uuid>/work-items/"
```

#### Get Single Work Item

```http
GET /workspaces/{workspace_slug}/projects/{project_id}/work-items/{work_item_id}/
```

#### Create Work Item

```http
POST /workspaces/{workspace_slug}/projects/{project_id}/work-items/
Content-Type: application/json
```

**Request Body:**

```json
{
  "name": "Issue title",
  "description_html": "<p>Description in HTML</p>",
  "priority": "medium",
  "state": "state-uuid",
  "assignees": ["user-uuid"],
  "labels": ["label-uuid"],
  "start_date": "2025-01-01",
  "target_date": "2025-01-15"
}
```

**Example:**

```bash
curl -X POST \
  -H "x-api-key: $PLANE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "New issue", "priority": "high"}' \
  "https://plane.lab.axiomlayer.com/api/v1/workspaces/axiomlayer/projects/<project-uuid>/work-items/"
```

#### Update Work Item

```http
PATCH /workspaces/{workspace_slug}/projects/{project_id}/work-items/{work_item_id}/
Content-Type: application/json
```

**Request Body (partial update):**

```json
{
  "priority": "urgent",
  "state": "new-state-uuid"
}
```

#### Delete Work Item

```http
DELETE /workspaces/{workspace_slug}/projects/{project_id}/work-items/{work_item_id}/
```

Returns `204 No Content` on success.

#### Work Item Fields

| Field | Type | Description |
|-------|------|-------------|
| id | uuid | Work item ID |
| name | string | Title |
| description_html | string | HTML description |
| priority | string | none, low, medium, high, urgent |
| state | uuid | State ID |
| sequence_id | int | Issue number (e.g., HOME-1) |
| assignees | array | List of user UUIDs |
| labels | array | List of label UUIDs |
| start_date | date | Start date (YYYY-MM-DD) |
| target_date | date | Due date (YYYY-MM-DD) |
| completed_at | datetime | Completion timestamp |
| parent | uuid | Parent issue ID |
| estimate_point | int | Story points |

---

### States

#### List States

```http
GET /workspaces/{workspace_slug}/projects/{project_id}/states/
```

**Example:**

```bash
curl -H "x-api-key: $PLANE_API_KEY" \
  "https://plane.lab.axiomlayer.com/api/v1/workspaces/axiomlayer/projects/<project-uuid>/states/"
```

#### Default States

Each project has default states. Use the API to retrieve state UUIDs for your project.

| State | Group | Color |
|-------|-------|-------|
| Backlog | backlog | #60646C |
| Todo | unstarted | #60646C |
| In Progress | started | #F59E0B |
| Done | completed | #46A758 |
| Cancelled | cancelled | #9AA4BC |

#### State Groups

| Group | Meaning |
|-------|---------|
| backlog | Not prioritized |
| unstarted | Prioritized but not started |
| started | In progress |
| completed | Done |
| cancelled | Won't do |

---

### Labels

#### List Labels

```http
GET /workspaces/{workspace_slug}/projects/{project_id}/labels/
```

#### Create Label

```http
POST /workspaces/{workspace_slug}/projects/{project_id}/labels/
Content-Type: application/json
```

**Request Body:**

```json
{
  "name": "bug",
  "color": "#FF5733",
  "description": "Bug reports"
}
```

#### Delete Label

```http
DELETE /workspaces/{workspace_slug}/projects/{project_id}/labels/{label_id}/
```

---

### Cycles (Sprints)

#### List Cycles

```http
GET /workspaces/{workspace_slug}/projects/{project_id}/cycles/
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| id | uuid | Cycle ID |
| name | string | Cycle name |
| start_date | datetime | Start date |
| end_date | datetime | End date |
| total_issues | int | Total issues |
| completed_issues | int | Completed count |
| started_issues | int | In progress count |
| backlog_issues | int | Backlog count |
| owned_by | uuid | Cycle owner |

---

### Modules

#### List Modules

```http
GET /workspaces/{workspace_slug}/projects/{project_id}/modules/
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| id | uuid | Module ID |
| name | string | Module name |
| description | string | Description |
| status | string | backlog, planned, in-progress, paused, completed, cancelled |
| start_date | date | Start date |
| target_date | date | Target date |
| total_issues | int | Total issues |
| lead | uuid | Module lead |
| members | array | Member UUIDs |

---

### Comments

#### List Comments

```http
GET /workspaces/{workspace_slug}/projects/{project_id}/work-items/{work_item_id}/comments/
```

#### Create Comment

```http
POST /workspaces/{workspace_slug}/projects/{project_id}/work-items/{work_item_id}/comments/
Content-Type: application/json
```

**Request Body:**

```json
{
  "comment_html": "<p>This is a comment</p>"
}
```

#### Delete Comment

```http
DELETE /workspaces/{workspace_slug}/projects/{project_id}/work-items/{work_item_id}/comments/{comment_id}/
```

---

### Activities

#### List Activities

```http
GET /workspaces/{workspace_slug}/projects/{project_id}/work-items/{work_item_id}/activities/
```

Activities are read-only and track all changes to a work item.

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| id | uuid | Activity ID |
| verb | string | created, updated |
| field | string | Changed field name |
| old_value | string | Previous value |
| new_value | string | New value |
| comment | string | Activity description |

---

### Links

#### List Links

```http
GET /workspaces/{workspace_slug}/projects/{project_id}/work-items/{work_item_id}/links/
```

#### Create Link

```http
POST /workspaces/{workspace_slug}/projects/{project_id}/work-items/{work_item_id}/links/
Content-Type: application/json
```

**Request Body:**

```json
{
  "title": "GitHub PR",
  "url": "https://github.com/org/repo/pull/123"
}
```

---

### Attachments

#### List Attachments

```http
GET /workspaces/{workspace_slug}/projects/{project_id}/work-items/{work_item_id}/attachments/
```

---

### Project Members

#### List Project Members

```http
GET /workspaces/{workspace_slug}/projects/{project_id}/members/
```

---

## Data Reference

### Priority Values

| Priority | Display |
|----------|---------|
| `none` | No priority |
| `low` | Low |
| `medium` | Medium |
| `high` | High |
| `urgent` | Urgent |

### Workspace ID

Retrieve dynamically via the API or from project responses.

---

## Example Scripts

### List All Open Issues

```bash
#!/bin/bash
source .env

WORKSPACE="axiomlayer"
PROJECT="<project-uuid>"  # Get from /workspaces/{slug}/projects/
DONE_STATE="<done-state-uuid>"  # Get from /projects/{id}/states/

curl -s -H "x-api-key: $PLANE_API_KEY" \
  "https://plane.lab.axiomlayer.com/api/v1/workspaces/$WORKSPACE/projects/$PROJECT/work-items/" \
  | jq ".results[] | select(.state != \"$DONE_STATE\") | {name, priority, sequence_id}"
```

### Create Issue from CLI

```bash
#!/bin/bash
source .env

WORKSPACE="axiomlayer"
PROJECT="<project-uuid>"
TITLE="$1"
PRIORITY="${2:-medium}"

curl -s -X POST \
  -H "x-api-key: $PLANE_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"$TITLE\", \"priority\": \"$PRIORITY\"}" \
  "https://plane.lab.axiomlayer.com/api/v1/workspaces/$WORKSPACE/projects/$PROJECT/work-items/" \
  | jq '{id, name, sequence_id}'
```

### Move Issue to Done

```bash
#!/bin/bash
source .env

WORKSPACE="axiomlayer"
PROJECT="<project-uuid>"
ISSUE_ID="$1"
DONE_STATE="<done-state-uuid>"  # Get from /projects/{id}/states/ where group=completed

curl -s -X PATCH \
  -H "x-api-key: $PLANE_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"state\": \"$DONE_STATE\"}" \
  "https://plane.lab.axiomlayer.com/api/v1/workspaces/$WORKSPACE/projects/$PROJECT/work-items/$ISSUE_ID/"
```

### Sync GitHub Issues to Plane

```bash
#!/bin/bash
# Sync open GitHub issues to Plane
source .env

WORKSPACE="axiomlayer"
PROJECT="<project-uuid>"
BASE="https://plane.lab.axiomlayer.com/api/v1/workspaces/$WORKSPACE/projects/$PROJECT"

gh issue list --json number,title,body --state open | jq -c '.[]' | while read -r issue; do
  TITLE=$(echo "$issue" | jq -r '.title')
  BODY=$(echo "$issue" | jq -r '.body // ""')
  NUMBER=$(echo "$issue" | jq -r '.number')

  curl -s -X POST \
    -H "x-api-key: $PLANE_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"GH#$NUMBER: $TITLE\", \"description_html\": \"<p>$BODY</p>\", \"external_id\": \"github-$NUMBER\"}" \
    "$BASE/work-items/"
done
```

---

## Troubleshooting

### 404 Not Found

- Verify workspace slug is correct (`axiomlayer`)
- Verify project ID is a valid UUID
- Check that the endpoint path is correct (trailing slashes matter)

### 401 Unauthorized

- Verify API key is set: `echo ${#PLANE_API_KEY}` (should show length)
- Verify API key hasn't expired
- Check header is `x-api-key` not `Authorization`

### Empty Results

- Check if project has the requested resources (cycles, modules, etc.)
- Some features may be disabled per-project (e.g., cycle_view: false)

### Rate Limiting

The self-hosted instance doesn't have strict rate limits, but avoid hammering the API with rapid requests.

---

## Related Documentation

- [Plane Official Docs](https://docs.plane.so)
- [APPLICATIONS.md](APPLICATIONS.md) - Application deployment details
- [SECRETS.md](SECRETS.md) - Secret management including PLANE_API_KEY
