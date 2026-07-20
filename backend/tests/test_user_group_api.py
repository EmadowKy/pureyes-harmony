import os
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch


BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

_tmpdir = tempfile.TemporaryDirectory()
os.environ["PUREYES_DISABLE_BACKGROUND"] = "1"
os.environ["DATABASE_URL"] = f"sqlite:///{Path(_tmpdir.name) / 'test_user_group.db'}"
sys.modules.setdefault("cv2", types.SimpleNamespace())

from app import create_app  # noqa: E402
from app.core.db import db  # noqa: E402


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
        self.assertEqual(stale_profile.status_code, 403, stale_profile.get_json())

        stale_group = self.client.post(
            "/api/groups/",
            headers=stale_headers,
            json={"name": "Should Not Create"},
        )
        self.assertEqual(stale_group.status_code, 403, stale_group.get_json())

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

            group = Group.query.get(group_id)
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
            self.assertEqual(monitor_payload["cover_url"], f"/api/monitors/{monitor_id}/cover")
            self.assertTrue(monitor_payload["cover_updated_at"])

            cover = self.client.get(f"/api/monitors/{monitor_id}/cover")
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
