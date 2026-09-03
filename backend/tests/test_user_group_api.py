import os
import sys
import json
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch


BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

_tmpdir = tempfile.TemporaryDirectory()
os.environ["PUREYES_DISABLE_BACKGROUND"] = "1"
os.environ["PUREYES_BOOTSTRAP_ADMIN_PASSWORD"] = "admin"
os.environ["DATABASE_URL"] = f"sqlite:///{Path(_tmpdir.name) / 'test_user_group.db'}"
sys.modules.setdefault("cv2", types.SimpleNamespace())

from app import create_app  # noqa: E402
from app.core.db import db  # noqa: E402
from app.core.tool_security import resolve_selected_video  # noqa: E402


class UserGroupApiTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app()
        cls.app.config["TESTING"] = True
        cls.client = cls.app.test_client()

        from app.monitors import routes as monitor_routes
        monitor_routes.BACKEND_ROOT = str(Path(_tmpdir.name))
        cls.recordings_base = Path(_tmpdir.name) / "recordings"
        cls.covers_base = Path(_tmpdir.name) / "covers"
        monitor_routes.RECORDINGS_BASE = str(cls.recordings_base)
        monitor_routes.COVERS_BASE = str(cls.covers_base)
        monitor_routes.start_recording = lambda monitor_id, stream_url: True
        monitor_routes.stop_recording = lambda monitor_id: None

        from app import video_stream_routes
        video_stream_routes.BACKEND_DIR = str(Path(_tmpdir.name))
        video_stream_routes.LIVE_STREAM_BASE = str(Path(_tmpdir.name) / "live")

    @classmethod
    def tearDownClass(cls):
        cls.client = None
        with cls.app.app_context():
            db.drop_all()
            db.session.remove()
            db.engine.dispose()
        try:
            _tmpdir.cleanup()
        except OSError:
            pass

    def auth_headers(self, emp_id, password):
        response = self.client.post(
            "/api/auth/login",
            json={"emp_id": emp_id, "password": password},
        )
        self.assertEqual(response.status_code, 200, response.get_json())
        token = response.get_json()["data"]["access_token"]
        return {"Authorization": f"Bearer {token}"}

    def create_user(self, emp_id, name, password="pass1234"):
        response = self.client.post(
            "/api/users/",
            headers=self.super_headers,
            json={"emp_id": emp_id, "name": name, "password": password},
        )
        self.assertEqual(response.status_code, 201, response.get_json())
        return response.get_json()["data"]

    def setUp(self):
        self.super_headers = self.auth_headers("admin", "admin")

    def test_admin_user_search_create_and_role_update(self):
        self.create_user("u_search", "Search Target")

        search = self.client.get(
            "/api/users/?keyword=search",
            headers=self.super_headers,
        )
        self.assertEqual(search.status_code, 200, search.get_json())
        users = search.get_json()["data"]
        self.assertEqual([u["emp_id"] for u in users], ["u_search"])

        role_update = self.client.put(
            "/api/users/u_search/role",
            headers=self.super_headers,
            json={"role": "admin"},
        )
        self.assertEqual(role_update.status_code, 200, role_update.get_json())
        self.assertEqual(role_update.get_json()["data"]["role"], "admin")

        promoted_headers = self.auth_headers("u_search", "pass1234")
        create_by_admin = self.client.post(
            "/api/users/",
            headers=promoted_headers,
            json={"emp_id": "admin_created", "name": "Created By Admin", "password": "pass1234"},
        )
        self.assertEqual(create_by_admin.status_code, 201, create_by_admin.get_json())

    def test_inactive_user_cannot_use_stale_token_or_login(self):
        self.create_user("inactive_case", "Inactive Case")
        stale_headers = self.auth_headers("inactive_case", "pass1234")

        disable = self.client.put(
            "/api/users/inactive_case/status",
            headers=self.super_headers,
            json={"is_active": False},
        )
        self.assertEqual(disable.status_code, 200, disable.get_json())
        self.assertFalse(disable.get_json()["data"]["is_active"])

        stale_profile = self.client.get("/api/users/me", headers=stale_headers)
        self.assertEqual(stale_profile.status_code, 401, stale_profile.get_json())

        stale_group = self.client.post(
            "/api/groups/",
            headers=stale_headers,
            json={"name": "Should Not Create"},
        )
        self.assertEqual(stale_group.status_code, 401, stale_group.get_json())

        login_again = self.client.post(
            "/api/auth/login",
            json={"emp_id": "inactive_case", "password": "pass1234"},
        )
        self.assertEqual(login_again.status_code, 403, login_again.get_json())

    def test_admin_cannot_disable_self(self):
        response = self.client.put(
            "/api/users/admin/status",
            headers=self.super_headers,
            json={"is_active": False},
        )
        self.assertEqual(response.status_code, 403, response.get_json())

    def test_admin_can_reset_and_delete_user_but_not_super_admin(self):
        self.create_user("managed_case", "Managed Case")
        self.create_user("admin_actor", "Admin Actor")
        role_update = self.client.put(
            "/api/users/admin_actor/role",
            headers=self.super_headers,
            json={"role": "admin"},
        )
        self.assertEqual(role_update.status_code, 200, role_update.get_json())

        admin_headers = self.auth_headers("admin_actor", "pass1234")
        reset = self.client.put(
            "/api/users/managed_case/password",
            headers=admin_headers,
            json={"password": "newpass123"},
        )
        self.assertEqual(reset.status_code, 200, reset.get_json())
        self.auth_headers("managed_case", "newpass123")

        blocked_reset = self.client.put(
            "/api/users/admin/password",
            headers=admin_headers,
            json={"password": "newpass123"},
        )
        self.assertEqual(blocked_reset.status_code, 403, blocked_reset.get_json())

        delete = self.client.delete(
            "/api/users/managed_case",
            headers=admin_headers,
        )
        self.assertEqual(delete.status_code, 200, delete.get_json())

        missing = self.client.get("/api/users/managed_case", headers=self.super_headers)
        self.assertEqual(missing.status_code, 404, missing.get_json())

        blocked_delete = self.client.delete("/api/users/admin", headers=admin_headers)
        self.assertEqual(blocked_delete.status_code, 403, blocked_delete.get_json())

    def test_delete_user_transfers_owned_groups_to_actor(self):
        self.create_user("group_owner_delete", "Group Owner Delete")
        self.create_user("delete_actor", "Delete Actor")
        role_update = self.client.put(
            "/api/users/delete_actor/role",
            headers=self.super_headers,
            json={"role": "admin"},
        )
        self.assertEqual(role_update.status_code, 200, role_update.get_json())

        owner_headers = self.auth_headers("group_owner_delete", "pass1234")
        group_response = self.client.post(
            "/api/groups/",
            headers=owner_headers,
            json={"name": "Transferred Group"},
        )
        self.assertEqual(group_response.status_code, 201, group_response.get_json())
        group_id = group_response.get_json()["data"]["id"]

        actor_headers = self.auth_headers("delete_actor", "pass1234")
        delete = self.client.delete(
            "/api/users/group_owner_delete",
            headers=actor_headers,
        )
        self.assertEqual(delete.status_code, 200, delete.get_json())

        with self.app.app_context():
            from app.models.group import Group, GroupMember
            from app.models.user import User

            group = db.session.get(Group, group_id)
            self.assertEqual(group.creator_id, "delete_actor")
            self.assertIsNone(User.query.filter_by(emp_id="group_owner_delete").first())
            actor_member = GroupMember.query.filter_by(
                group_id=group_id,
                emp_id="delete_actor",
                status="accepted",
            ).first()
            self.assertIsNotNone(actor_member)

    def test_regular_user_can_search_users_read_only(self):
        self.create_user("public_actor", "Public Actor")
        self.create_user("public_target", "Public Target")
        actor_headers = self.auth_headers("public_actor", "pass1234")

        search = self.client.get(
            "/api/users/search?keyword=public_target",
            headers=actor_headers,
        )
        self.assertEqual(search.status_code, 200, search.get_json())
        users = search.get_json()["data"]
        self.assertEqual([u["emp_id"] for u in users], ["public_target"])
        self.assertIn("phone", users[0])
        self.assertNotIn("llm_api_key", users[0])
        self.assertNotIn("llm_base_url", users[0])
        self.assertNotIn("llm_model", users[0])

        admin_search = self.client.get(
            "/api/users/?keyword=public_target",
            headers=actor_headers,
        )
        self.assertEqual(admin_search.status_code, 403, admin_search.get_json())

        forbidden_delete = self.client.delete(
            "/api/users/public_target",
            headers=actor_headers,
        )
        self.assertEqual(forbidden_delete.status_code, 403, forbidden_delete.get_json())

    def test_api_key_is_only_reported_as_configured(self):
        self.create_user("api_owner", "API Owner")
        self.create_user("api_viewer", "API Viewer")
        owner_headers = self.auth_headers("api_owner", "pass1234")
        viewer_headers = self.auth_headers("api_viewer", "pass1234")

        configured = self.client.put(
            "/api/users/me",
            headers=owner_headers,
            json={
                "llm_api_key": "sentinel-secret-key",
                "llm_base_url": "https://example.invalid/v1",
                "llm_model": "vision-model",
            },
        )
        self.assertEqual(configured.status_code, 200, configured.get_json())
        own_payload = configured.get_json()["data"]
        self.assertTrue(own_payload["llm_api_key_configured"])
        self.assertNotIn("llm_api_key", own_payload)
        with self.app.app_context():
            from sqlalchemy import text

            stored_key = db.session.execute(text(
                "SELECT llm_api_key FROM users WHERE emp_id = 'api_owner'"
            )).scalar_one()
            self.assertTrue(stored_key.startswith("enc:v1:"))
            self.assertNotIn("sentinel-secret-key", stored_key)

        group_response = self.client.post(
            "/api/groups/",
            headers=owner_headers,
            json={"name": "API Privacy Group"},
        )
        group_id = group_response.get_json()["data"]["id"]
        self.client.post(
            f"/api/groups/{group_id}/invite",
            headers=owner_headers,
            json={"emp_id": "api_viewer"},
        )
        self.client.post(
            f"/api/groups/{group_id}/respond",
            headers=viewer_headers,
            json={"action": "accept"},
        )

        visible_profile = self.client.get("/api/users/api_owner", headers=viewer_headers)
        self.assertEqual(visible_profile.status_code, 200, visible_profile.get_json())
        self.assertNotIn("llm_api_key", visible_profile.get_json()["data"])
        self.assertNotIn("llm_base_url", visible_profile.get_json()["data"])

        members = self.client.get(f"/api/groups/{group_id}/members", headers=viewer_headers)
        serialized = str(members.get_json())
        self.assertNotIn("sentinel-secret-key", serialized)
        self.assertNotIn("llm_api_key", serialized)

        cleared = self.client.put(
            "/api/users/me",
            headers=owner_headers,
            json={"clear_llm_api_key": True},
        )
        self.assertEqual(cleared.status_code, 200, cleared.get_json())
        self.assertFalse(cleared.get_json()["data"]["llm_api_key_configured"])

    def test_llm_base_url_rejects_plain_http_and_private_addresses(self):
        self.create_user("llm_url_case", "LLM URL Case")
        headers = self.auth_headers("llm_url_case", "pass1234")

        for unsafe_url in ["http://example.com/v1", "https://127.0.0.1/v1", "file:///tmp/model"]:
            response = self.client.put(
                "/api/users/me",
                headers=headers,
                json={"llm_base_url": unsafe_url},
            )
            self.assertEqual(response.status_code, 400, (unsafe_url, response.get_json()))

        safe = self.client.put(
            "/api/users/me",
            headers=headers,
            json={"llm_base_url": "https://example.invalid/v1"},
        )
        self.assertEqual(safe.status_code, 200, safe.get_json())

    def test_agent_tool_paths_are_limited_to_selected_videos(self):
        selected = [{
            "video_id": "selected.mp4",
            "video_path": str(Path(_tmpdir.name) / "selected.mp4"),
        }]
        self.assertIsNotNone(resolve_selected_video(selected, {"video_id": "selected.mp4"}))
        self.assertIsNone(resolve_selected_video(selected, {"video_id": "other.mp4"}))
        self.assertIsNone(resolve_selected_video(selected, {"video_path": "C:/Windows/System32/config/SAM"}))

    def test_logout_revokes_refresh_token(self):
        self.create_user("logout_case", "Logout Case")
        login = self.client.post(
            "/api/auth/login",
            json={"emp_id": "logout_case", "password": "pass1234"},
        )
        tokens = login.get_json()["data"]
        logout = self.client.post(
            "/api/auth/logout",
            headers={"Authorization": f"Bearer {tokens['access_token']}"},
        )
        self.assertEqual(logout.status_code, 200, logout.get_json())

        refresh = self.client.post(
            "/api/auth/refresh",
            headers={"Authorization": f"Bearer {tokens['refresh_token']}"},
        )
        self.assertEqual(refresh.status_code, 401, refresh.get_json())

    def test_workspace_private_routes_reject_outsiders(self):
        self.create_user("workspace_owner", "Workspace Owner")
        self.create_user("workspace_outsider", "Workspace Outsider")
        owner_headers = self.auth_headers("workspace_owner", "pass1234")
        outsider_headers = self.auth_headers("workspace_outsider", "pass1234")

        group_response = self.client.post(
            "/api/groups/",
            headers=owner_headers,
            json={"name": "Private Workspace Group"},
        )
        group_id = group_response.get_json()["data"]["id"]
        workspace_response = self.client.post(
            f"/api/workspaces/{group_id}",
            headers=owner_headers,
            json={"name": "Private Workspace"},
        )
        workspace_id = workspace_response.get_json()["data"]["id"]

        with self.app.app_context():
            from app.models.qa_record import QARecord
            from app.models.workspace import WorkspaceVideoSegment

            record = QARecord(
                id="private-task",
                workspace_id=workspace_id,
                creator_id="workspace_owner",
                question="private question",
                answer="private answer",
                status="completed",
            )
            segment = WorkspaceVideoSegment(
                workspace_id=workspace_id,
                video_name="private.mp4",
                start_offset=0,
                end_offset=1,
                duration=1,
                filepath="storage/slices/private.mp4",
            )
            db.session.add_all([record, segment])
            db.session.commit()
            segment_id = segment.id

        protected_paths = [
            f"/api/workspaces/{workspace_id}/faces",
            f"/api/workspaces/{workspace_id}/faces/1/records",
            "/api/workspaces/qa/private-task/status",
        ]
        for path in protected_paths:
            response = self.client.get(path, headers=outsider_headers)
            self.assertEqual(response.status_code, 403, (path, response.get_json()))

        preprocess = self.client.post(
            f"/api/workspaces/segments/{segment_id}/preprocess",
            headers=outsider_headers,
            json={"sample_fps": 1, "resolution": "720P"},
        )
        self.assertEqual(preprocess.status_code, 403, preprocess.get_json())

        clear_features = self.client.delete(
            f"/api/workspaces/segments/{segment_id}/features",
            headers=outsider_headers,
        )
        self.assertEqual(clear_features.status_code, 403, clear_features.get_json())

        anonymous_stream = self.client.get("/api/workspaces/qa/private-task/stream")
        self.assertEqual(anonymous_stream.status_code, 401)
        outsider_stream = self.client.get(
            "/api/workspaces/qa/private-task/stream",
            headers=outsider_headers,
        )
        self.assertEqual(outsider_stream.status_code, 403)

        invalid_fps = self.client.post(
            f"/api/workspaces/segments/{segment_id}/preprocess",
            headers=owner_headers,
            json={"sample_fps": "nan", "resolution": "720P"},
        )
        self.assertEqual(invalid_fps.status_code, 400, invalid_fps.get_json())

        invalid_qa = self.client.post(
            f"/api/workspaces/{workspace_id}/qa",
            headers=owner_headers,
            json={"question": "test", "segment_ids": "not-a-list"},
        )
        self.assertEqual(invalid_qa.status_code, 400, invalid_qa.get_json())

    def test_spatiotemporal_database_replaces_records_atomically(self):
        from app.mva_v2 import database as database_module

        old_path = database_module.DB_FILE_PATH
        old_loaded_path = database_module.SpatiotemporalDB._loaded_path
        old_records = list(database_module.SpatiotemporalDB._shared_records)
        try:
            with tempfile.TemporaryDirectory() as temp_dir:
                database_module.DB_FILE_PATH = str(Path(temp_dir) / "features.json")
                database_module.SpatiotemporalDB._loaded_path = None
                database_module.SpatiotemporalDB._shared_records.clear()

                feature_db = database_module.SpatiotemporalDB()
                first_record = {
                    "video_id": "clip.mp4",
                    "workspace_id": 9,
                    "timestamp": 1.0,
                    "track_id": "track_1",
                    "class_name": "person",
                    "reid_vector": [1.0, 0.0],
                }
                feature_db.replace_video_records("clip.mp4", [first_record], workspace_id=9)

                replacement = dict(first_record)
                replacement["timestamp"] = 2.0
                feature_db.replace_video_records("clip.mp4", [replacement], workspace_id=9)

                with open(database_module.DB_FILE_PATH, "r", encoding="utf-8") as stored_file:
                    stored = json.load(stored_file)
                self.assertEqual(len(stored), 1)
                self.assertEqual(stored[0]["timestamp"], 2.0)

                second_client = database_module.SpatiotemporalDB()
                self.assertIs(second_client.records, feature_db.records)
                self.assertEqual(second_client.delete_video("clip.mp4", workspace_id=9), 1)
                with open(database_module.DB_FILE_PATH, "r", encoding="utf-8") as stored_file:
                    self.assertEqual(json.load(stored_file), [])
        finally:
            database_module.DB_FILE_PATH = old_path
            database_module.SpatiotemporalDB._loaded_path = old_loaded_path
            database_module.SpatiotemporalDB._shared_records.clear()
            database_module.SpatiotemporalDB._shared_records.extend(old_records)

    def test_media_urls_require_scoped_tokens_and_membership(self):
        self.create_user("media_owner", "Media Owner")
        self.create_user("media_member", "Media Member")
        owner_headers = self.auth_headers("media_owner", "pass1234")
        member_headers = self.auth_headers("media_member", "pass1234")

        group_response = self.client.post(
            "/api/groups/",
            headers=owner_headers,
            json={"name": "Protected Media Group"},
        )
        group_id = group_response.get_json()["data"]["id"]
        self.client.post(
            f"/api/groups/{group_id}/invite",
            headers=owner_headers,
            json={"emp_id": "media_member"},
        )
        self.client.post(
            f"/api/groups/{group_id}/respond",
            headers=member_headers,
            json={"action": "accept"},
        )
        workspace_response = self.client.post(
            f"/api/workspaces/{group_id}",
            headers=owner_headers,
            json={"name": "Protected Media Workspace"},
        )
        workspace_id = workspace_response.get_json()["data"]["id"]

        media_file = Path(_tmpdir.name) / "storage" / "slices" / "protected.mp4"
        media_file.parent.mkdir(parents=True, exist_ok=True)
        media_file.write_bytes(b"not-a-real-video")

        with self.app.app_context():
            from app.models.workspace import WorkspaceVideoSegment

            segment = WorkspaceVideoSegment(
                workspace_id=workspace_id,
                video_name="protected.mp4",
                start_offset=0,
                end_offset=1,
                duration=1,
                filepath="storage/slices/protected.mp4",
            )
            db.session.add(segment)
            db.session.commit()

        anonymous = self.client.get("/api/video/storage/slices/protected.mp4?check=1")
        self.assertEqual(anonymous.status_code, 401)

        listed = self.client.get(
            f"/api/workspaces/{workspace_id}/segments",
            headers=member_headers,
        )
        media_url = listed.get_json()["data"][0]["media_url"]
        self.assertIn("media_token=", media_url)
        signed = self.client.get(f"{media_url}&check=1")
        self.assertEqual(signed.status_code, 200, signed.get_json())

        removed = self.client.delete(
            f"/api/groups/{group_id}/members/media_member",
            headers=owner_headers,
        )
        self.assertEqual(removed.status_code, 200, removed.get_json())
        revoked = self.client.get(f"{media_url}&check=1")
        self.assertEqual(revoked.status_code, 401)

    def test_group_invitation_acceptance_and_membership_visibility(self):
        self.create_user("leader", "Group Leader")
        self.create_user("member", "Group Member")
        leader_headers = self.auth_headers("leader", "pass1234")
        member_headers = self.auth_headers("member", "pass1234")

        group_response = self.client.post(
            "/api/groups/",
            headers=leader_headers,
            json={"name": "Case Team"},
        )
        self.assertEqual(group_response.status_code, 201, group_response.get_json())
        group_id = group_response.get_json()["data"]["id"]

        invite_response = self.client.post(
            f"/api/groups/{group_id}/invite",
            headers=leader_headers,
            json={"emp_id": "member"},
        )
        self.assertEqual(invite_response.status_code, 201, invite_response.get_json())
        self.assertEqual(invite_response.get_json()["data"]["status"], "pending")

        invites = self.client.get("/api/groups/invites", headers=member_headers)
        self.assertEqual(invites.status_code, 200, invites.get_json())
        self.assertEqual(invites.get_json()["data"][0]["group_id"], group_id)

        accept_response = self.client.post(
            f"/api/groups/{group_id}/respond",
            headers=member_headers,
            json={"action": "accept"},
        )
        self.assertEqual(accept_response.status_code, 200, accept_response.get_json())

        members = self.client.get(
            f"/api/groups/{group_id}/members",
            headers=member_headers,
        )
        self.assertEqual(members.status_code, 200, members.get_json())
        member_ids = {m["emp_id"] for m in members.get_json()["data"]}
        self.assertEqual(member_ids, {"leader", "member"})

        visible_profile = self.client.get("/api/users/leader", headers=member_headers)
        self.assertEqual(visible_profile.status_code, 200, visible_profile.get_json())

    def test_monitor_creation_is_creator_only_and_history_uses_recordings(self):
        self.create_user("monitor_leader", "Monitor Leader")
        self.create_user("monitor_member", "Monitor Member")
        leader_headers = self.auth_headers("monitor_leader", "pass1234")
        member_headers = self.auth_headers("monitor_member", "pass1234")

        group_response = self.client.post(
            "/api/groups/",
            headers=leader_headers,
            json={"name": "Camera Team"},
        )
        self.assertEqual(group_response.status_code, 201, group_response.get_json())
        group_id = group_response.get_json()["data"]["id"]

        invite_response = self.client.post(
            f"/api/groups/{group_id}/invite",
            headers=leader_headers,
            json={"emp_id": "monitor_member"},
        )
        self.assertEqual(invite_response.status_code, 201, invite_response.get_json())

        accept_response = self.client.post(
            f"/api/groups/{group_id}/respond",
            headers=member_headers,
            json={"action": "accept"},
        )
        self.assertEqual(accept_response.status_code, 200, accept_response.get_json())

        forbidden_create = self.client.post(
            f"/api/monitors/{group_id}",
            headers=member_headers,
            json={"name": "Gate Camera", "stream_url": "rtsp://example/live"},
        )
        self.assertEqual(forbidden_create.status_code, 403, forbidden_create.get_json())

        allowed_create = self.client.post(
            f"/api/monitors/{group_id}",
            headers=leader_headers,
            json={"name": "Gate Camera", "stream_url": "rtsp://example/live"},
        )
        self.assertEqual(allowed_create.status_code, 201, allowed_create.get_json())
        monitor_id = allowed_create.get_json()["data"]["id"]

        forbidden_update = self.client.put(
            f"/api/monitors/{monitor_id}",
            headers=member_headers,
            json={"name": "Gate Camera Updated", "stream_url": "rtsp://example/updated"},
        )
        self.assertEqual(forbidden_update.status_code, 403, forbidden_update.get_json())

        allowed_update = self.client.put(
            f"/api/monitors/{monitor_id}",
            headers=leader_headers,
            json={"name": "Gate Camera Updated", "stream_url": "rtsp://example/updated"},
        )
        self.assertEqual(allowed_update.status_code, 200, allowed_update.get_json())
        self.assertEqual(allowed_update.get_json()["data"]["name"], "Gate Camera Updated")
        self.assertEqual(allowed_update.get_json()["data"]["stream_url"], "rtsp://example/updated")

        recordings_dir = self.recordings_base / str(monitor_id)
        recordings_dir.mkdir(parents=True, exist_ok=True)
        recording_name = "20260712_120000.mp4"
        (recordings_dir / recording_name).write_bytes(b"")

        history = self.client.get(
            f"/api/monitors/{monitor_id}/history?anchor=2026-07-12T12:00:30&granularity=minute&window=2",
            headers=member_headers,
        )
        self.assertEqual(history.status_code, 200, history.get_json())
        payload = history.get_json()["data"]
        self.assertEqual(payload["selected_record"]["filename"], recording_name)
        self.assertTrue(payload["records"])

        playback = self.client.get(
            f"/api/monitors/{monitor_id}/playback?time=2026-07-12T12:00:30",
            headers=member_headers,
        )
        self.assertEqual(playback.status_code, 200, playback.get_json())
        self.assertEqual(playback.get_json()["data"]["record"]["filename"], recording_name)

        cover_recording_name = "20260712_120100.mp4"
        (recordings_dir / cover_recording_name).write_bytes(b"fake-video")

        from app.monitors import routes as monitor_routes

        def fake_ffmpeg(cmd, capture_output, text, timeout):
            Path(cmd[-1]).write_bytes(b"fake-jpeg")
            return types.SimpleNamespace(returncode=0, stderr="")

        with patch.object(monitor_routes.subprocess, "run", side_effect=fake_ffmpeg):
            listed = self.client.get(
                f"/api/monitors/{group_id}",
                headers=member_headers,
            )
            self.assertEqual(listed.status_code, 200, listed.get_json())
            monitor_payload = listed.get_json()["data"][0]
            self.assertTrue(monitor_payload["cover_url"].startswith(f"/api/monitors/{monitor_id}/cover?media_token="))
            self.assertTrue(monitor_payload["cover_updated_at"])

            cover = self.client.get(monitor_payload["cover_url"])
            self.assertEqual(cover.status_code, 200, cover.get_json() if cover.is_json else cover.status)
            self.assertEqual(cover.mimetype, "image/jpeg")

        forbidden_delete = self.client.delete(
            f"/api/monitors/{monitor_id}",
            headers=member_headers,
        )
        self.assertEqual(forbidden_delete.status_code, 403, forbidden_delete.get_json())

        allowed_delete = self.client.delete(
            f"/api/monitors/{monitor_id}",
            headers=leader_headers,
        )
        self.assertEqual(allowed_delete.status_code, 200, allowed_delete.get_json())
        self.assertFalse(recordings_dir.exists())
        self.assertFalse((self.covers_base / f"{monitor_id}.jpg").exists())


if __name__ == "__main__":
    unittest.main()
