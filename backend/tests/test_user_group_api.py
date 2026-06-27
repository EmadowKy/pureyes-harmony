import os
import sys
import tempfile
import types
import unittest
from pathlib import Path


BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

_tmpdir = tempfile.TemporaryDirectory()
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

    @classmethod
    def tearDownClass(cls):
        with cls.app.app_context():
            db.session.remove()
            db.drop_all()
        _tmpdir.cleanup()

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


if __name__ == "__main__":
    unittest.main()
