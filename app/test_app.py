import unittest

import app


class RouteTest(unittest.TestCase):
    def test_health_reporta_versao(self):
        status, body = app.route("/health")
        self.assertEqual(status, 200)
        self.assertEqual(body["status"], "ok")
        self.assertIn("version", body)

    def test_raiz_reporta_ambiente(self):
        status, body = app.route("/")
        self.assertEqual(status, 200)
        self.assertEqual(body["app"], "web-api")
        self.assertIn("env", body)

    def test_rota_desconhecida(self):
        status, _ = app.route("/nao-existe")
        self.assertEqual(status, 404)


if __name__ == "__main__":
    unittest.main()
