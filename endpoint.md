# Clip API Endpoint Specification

Backend API contract for video upload, metadata retrieval, and search.

---

## Endpoints

### 1. GET /api/videos - Get All Videos (Primary)

**This is the main endpoint the app uses on launch.** Returns metadata + transcript for all processed videos.

**Query Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `limit` | integer | Max results (default: 50) |
| `offset` | integer | Pagination offset (default: 0) |

**Response:**

```json
{
  "videos": [
    {
      "videoId": "PHAsset-XXXX-XXXX",
      "title": "Coffee with Sarah",
      "timestamp": "2026-01-17T10:30:00Z",
      "duration": 58,
      "tags": ["coffee", "friends", "conversation"],
      "transcript": "Hey! It's been so long. How's the new job going? I heard you got promoted..."
    },
    {
      "videoId": "PHAsset-YYYY-YYYY",
      "title": "Hackathon Demo",
      "timestamp": "2026-01-17T08:15:00Z",
      "duration": 60,
      "tags": ["coding", "hackathon", "demo"],
      "transcript": "So what we built is an AI-powered clip search..."
    }
  ],
  "total": 2,
  "hasMore": false
}
```

---

### 2. POST /api/video - Upload Video

Upload a new video clip with raw bytes for processing.

**Request:**

```json
{
  "videoId": "PHAsset-XXXX-XXXX",
  "title": "Coffee with Sarah",
  "timestamp": "2026-01-17T10:30:00Z",
  "videoData": "<base64 encoded bytes>"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `videoId` | string | Yes | iPhone local identifier (PHAsset) |
| `title` | string | Yes | User-provided or auto-generated title |
| `timestamp` | ISO 8601 | Yes | When the clip was captured |
| `videoData` | base64 | Yes | Raw video bytes |

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

### 3. GET /api/video/:videoId - Get Single Video

Retrieve full metadata + transcript for a specific video.

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
  "duration": 58,
  "tags": ["coffee", "friends", "conversation"],
  "transcript": "Hey! It's been so long. How's the new job going? I heard you got promoted. That's amazing! We should definitely do dinner next week."
}
```

---

### 4. GET /api/search - Search Videos

Search by natural text OR filter by tag.

**Query Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `type` | string | `"tag"` or `"stringsearch"` |
| `input` | string | The tag name or search query |

**Examples:**

```
GET /api/search?type=stringsearch&input=coffee with sarah
GET /api/search?type=tag&input=coffee
GET /api/search?type=stringsearch&input=hackathon demo
```

**Response:**

```json
{
  "results": [
    {
      "videoId": "PHAsset-XXXX-XXXX",
      "title": "Coffee with Sarah",
      "timestamp": "2026-01-17T10:30:00Z",
      "duration": 58,
      "tags": ["coffee", "friends"],
      "transcript": "Hey! It's been so long..."
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
