import json

from hello_world import app


def test_gera_guia_com_requisicao_valida():
    evento = {"body": json.dumps({"requisicaoId": "R-001",
                                  "hospital": "H-Recife",
                                  "bolsas": ["O-NEG-0142"]})}

    ret = app.lambda_handler(evento, None)
    guia = json.loads(ret["body"])

    assert ret["statusCode"] == 201
    assert guia["guia"] == "G-R-001"
    assert guia["hospital"] == "H-Recife"
    assert guia["bolsas"] == ["O-NEG-0142"]
    assert guia["invocacaoNesteAmbiente"] >= 1


def test_rejeita_requisicao_sem_id():
    ret = app.lambda_handler({"body": json.dumps({"hospital": "H-Recife"})}, None)

    assert ret["statusCode"] == 400
    assert "requisicaoId" in json.loads(ret["body"])["erro"]


def test_rejeita_body_vazio():
    ret = app.lambda_handler({"body": None}, None)

    assert ret["statusCode"] == 400
