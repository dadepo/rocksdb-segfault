use rust_rocksdb::{ColumnFamilyDescriptor, Options, WriteBatch, DB};
use std::error::Error;

fn main() -> Result<(), Box<dyn Error>> {
    let path = "_path_for_rocksdb_storage";

    let mut options = Options::default();
    options.create_if_missing(true);
    options.create_missing_column_families(true);

    let cfs = vec![ColumnFamilyDescriptor::new("default", Options::default())];
    let db = DB::open_cf_descriptors(&options, path, cfs)?;

    let cf_handle = db.cf_handle("default").ok_or("Column family not found")?;

    let delete_start = [182u8, 28, 212, 119];
    let delete_end = [190u8, 147, 84, 76];
    let get_key = [61u8, 84, 191, 167, 182, 191, 187, 206];

    let mut batch = WriteBatch::default();

    batch.delete_range_cf(cf_handle, &delete_start, &delete_end);

    db.write(batch)?;

    if let Some(value) = db.get_cf(cf_handle, &get_key)? {
        println!("Retrieved value: {:?}", value);
    } else {
        println!("Key not found");
    }

    Ok(())
}
