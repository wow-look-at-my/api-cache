mod helper;
pub const K: &str = env!("PATH_LIKE_VAR", "unset-default");
pub fn f() -> i32 { helper::g() + include!("inc.txt") }
