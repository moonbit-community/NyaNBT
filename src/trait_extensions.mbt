///|
pub extend Reader with @io.Reader::{read}

///|
pub extend Reader with @io.Closer::{close}

///|
pub extend Reader with Resetter::{reset}
