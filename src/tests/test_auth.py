class TestLogin:
    def test_login_success(self, client, registered_user):
        response = client.post(
            "/auth/login",
            json={"email": registered_user.email, "password": "password123"},
        )

        assert response.status_code == 200
        assert response.json()["access_token"]

    def test_login_wrong_password(self, client, registered_user):
        response = client.post(
            "/auth/login",
            json={"email": registered_user.email, "password": "wrong-password"},
        )

        assert response.status_code == 401
        assert (
            response.json()["detail"]
            == "メールアドレスまたはパスワードが正しくありません"
        )

    def test_login_unknown_email(self, client):
        response = client.post(
            "/auth/login",
            json={"email": "not-registered@example.com", "password": "password123"},
        )

        assert response.status_code == 401
        assert (
            response.json()["detail"]
            == "メールアドレスまたはパスワードが正しくありません"
        )
