let fsm = variable::get("fsm_name");
if fsm.starts_with("uc_") {
    abort("fsm_name must not start with `uc_`: that prefix is reserved for ultima_cluster's own state machines");
}
let project = variable::get("project-name");
if project == "app" {
    abort("project name `app` collides with the library crate `app`; pick another name");
}
let port = parse_int(variable::get("base_port"));
if port + 202 > 65535 {
    abort("base_port too high: the metrics band ends at base_port + 202, which must be <= 65535");
}
