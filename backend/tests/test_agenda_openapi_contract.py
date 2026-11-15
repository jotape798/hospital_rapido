"""Contrato OpenAPI das agendas, perfis e rotas oficiais."""

from test_integration import client


def test_agenda_routes_document_authorized_profiles_and_errors(client):
    paths = client.get("/openapi.json").json()["paths"]
    expected = {
        ("/appointments/me", "get"): ({"Paciente"}, {"401", "403"}),
        ("/queue", "get"): (
            {"Recepção", "Enfermagem", "Médico", "Administrador"},
            {"401", "403", "422"},
        ),
        ("/admin/appointments", "get"): (
            {"Administrador", "Recepção", "Profissional"},
            {"401", "403", "422"},
        ),
        ("/recepcao/agendamentos", "get"): (
            {"Recepção"},
            {"401", "403", "422"},
        ),
        ("/enfermagem/fila", "get"): (
            {"Enfermagem"},
            {"401", "403", "422"},
        ),
        ("/medico/fila", "get"): (
            {"Médico", "Profissional"},
            {"401", "403"},
        ),
    }
    for (path, method), (profiles, responses) in expected.items():
        operation = paths[path][method]
        description = operation.get("description", "")
        assert all(profile in description for profile in profiles), path
        assert responses <= set(operation["responses"]), path


def test_equivalent_agenda_actions_remain_unified(client):
    paths = client.get("/openapi.json").json()["paths"]
    checkins = [path for path in paths if path.endswith("/check-in")]
    assert checkins == ["/recepcao/agendamentos/{appointment_id}/check-in"]
    assert set(paths["/appointments"]) == {"post"}
    assert "/admin/appointments/{appointment_id}/check-in" not in paths
    assert "/appointments/{appointment_id}/status" not in paths


def test_priority_validation_openapi_lists_applicable_responses(client):
    operation = client.get("/openapi.json").json()["paths"][
        "/recepcao/agendamentos/{appointment_id}/condicoes/{condition_name}/validacao"
    ]["patch"]
    assert "Recepção" in operation["description"]
    assert {"401", "403", "404", "409", "422"} <= set(operation["responses"])
