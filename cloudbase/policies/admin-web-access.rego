package authz.user

# Candidate only: requires Sam's confirmation before setPolicy.
# Keep platform defaults for authenticated users and service identities.
allow if {
    input.cloudbase.env_id == "{{ENV_ID}}"
    input.cloudbase.entrypoint_type == "tcbopenapi"
    input.cloudbase.resource_type == "functions"
    input.request.method == "POST"
    input.request.path == "/v1/functions/shop"
    input.subject.auth_type in {"anon", "anonymous", "authenticated"}
}

# Publishable-key visitors may only reach the read-only shop function.
deny contains "Please use the WeChat mini program to sign in" if {
    input.cloudbase.resource_type == "functions"
    input.subject.auth_type in {"anon", "anonymous", "unauthenticated"}
    input.subject.user_id in {"", "anon"}
    input.request.path != "/v1/functions/shop"
    input.request.path != "/v1/functions/admin"
}

deny contains "Internal automation endpoint" if {
    input.cloudbase.resource_type == "functions"
    input.request.path in {"/v1/functions/timer", "/v1/functions/maintenance"}
    not input.subject.auth_type in {"administrator", "service_role", "internal"}
}

# Route A: only admin; its non-login actions require a server-validated token.
allow if {
    input.cloudbase.env_id == "{{ENV_ID}}"
    input.cloudbase.entrypoint_type == "tcbopenapi"
    input.cloudbase.resource_type == "functions"
    input.request.method == "POST"
    input.request.path == "/v1/functions/admin"
    input.subject.auth_type in {"anon", "anonymous", "authenticated"}
}