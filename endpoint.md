# Clip API Endpoint Specification

Backend API contract for video upload, metadata retrieval, and search.

---

## Endpoints

### 1. POST /api/video - Upload Video

Upload a new video clip with raw bytes.

**Request:**

```json
{
  "videoId": "PHAsset-XXXX-XXXX",
  "title": "Coffee with Sarah",
  "timestamp": "2026-01-17T10:30:00Z",
  "videoData": "<base64 encoded bytes>",
  "audioData": "<base64 encoded bytes>"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `videoId` | string | Yes | iPhone local identifier (PHAsset) |
| `title` | string | Yes | User-provided or auto-generated title |
| `timestamp` | ISO 8601 | Yes | When the clip was captured |
| `videoData` | base64 | Yes | Raw video bytes |
| `audioData` | base64 | No | Raw audio bytes (optional if embedded in video) |

**Response:**

```json
{
  "success": true,
  "videoId": "PHAsset-XXXX-XXXX",
  "tags": ["coffee", "friends", "conversation"],
  "transcript": "Hey! It's been so long..."
}
```

---

### 2. GET /api/video/:videoId - Get Video Metadata

Retrieve metadata for a specific video.

**Path Parameters:**

| Parameter | Description |
|-----------|-------------|
| `videoId` | iPhone local identifier (PHAsset) |

**Response:**

```json
{
  "videoId": "PHAsset-XXXX-XXXX",
  "title": "Coffee with Sarah",
  "timestamp": "2026-01-17T10:30:00Z",
  "tags": ["coffee", "friends", "conversation"],
  "duration": 30
}
```

---

### 3. GET /api/search - Search Videos

Search by natural text OR filter by tags (single endpoint).

**Query Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `q` | string | Natural language search query |
| `tags` | JSON array | Tags to filter by |
| `limit` | integer | Max results (default: 20) |

**Examples:**

```
GET /api/search?q=coffee with sarah
GET /api/search?tags=["coffee","friends"]
GET /api/search?q=meeting&tags=["work"]
```

**Response:**

```json
{
  "results": [
    {
      "videoId": "PHAsset-XXXX-XXXX",
      "title": "Coffee with Sarah",
      "timestamp": "2026-01-17T10:30:00Z",
      "tags": ["coffee", "friends"]
    }
  ],
  "total": 1
}
```

---

## Error Responses

All endpoints return errors in this format:

```json
{
  "success": false,
  "error": "Video not found",
  "code": "NOT_FOUND"
}
```

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `NOT_FOUND` | 404 | Resource not found |
| `BAD_REQUEST` | 400 | Invalid request parameters |
| `SERVER_ERROR` | 500 | Internal server error |
