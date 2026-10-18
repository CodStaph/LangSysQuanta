trait Read {
    fn read(self: ref[Self], dst: ref[Slice[U8]]) -> Result[USize, Error] eff(Read)
}

impl Read for File {
    fn read(self: ref[File], dst: ref[Slice[U8]]) -> Result[USize, Error] eff(Read) { ... }
}
