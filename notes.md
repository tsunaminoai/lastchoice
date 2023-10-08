# Notes to self

## Useful functions to look at in `std.mem`

### window

/// Returns an iterator with a sliding window of slices for `buffer`.
/// The sliding window has length `size` and on every iteration moves
/// forward by `advance`.

### bytesAsValue / bytesToValue

/// Given a pointer to an array of bytes, returns a pointer to a value of the specified type
/// backed by those bytes, preserving pointer attributes.

---

/// Given a pointer to an array of bytes, returns a value of the specified type backed by a
/// copy of those bytes.
