# Lessons Learned

- Verify runtime gem API against the actual containerized version before finalizing implementation. In this project, `mini_magick` 5.3.1 requires using helpers like `MiniMagick.convert` (or passing a tool name), so `MiniMagick::Tool::Magick.new` without arguments breaks at runtime.
