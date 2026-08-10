# Customer Flow Admin Panel

Responsive browser interface for managing Customer Flow users, agencies, patient cases and doctor assignments. The panel has no separate backend; it signs in through the Customer Flow API.

## Simple setup

1. Keep this folder next to the `api/` folder.
2. Start the API by following [`../api/README.md`](../api/README.md).
3. Open `http://localhost:8080/admin`.
4. Sign in with an administrator account created on the server.

The API serves `index.html`, `admin.css` and `admin.js` from this folder by default. If the panel is stored elsewhere on the server, set `CF_ADMIN_DIR` to its absolute path before starting the API.

For production, expose both the panel and API through HTTPS. Do not place passwords, server tokens or patient data in these static files.
