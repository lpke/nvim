return {
  -- Snippets whose triggers start with one of these get priority over regular
  -- snippets when both match the text before the cursor.
  priority_prefixes = { '.', '-', '_', '=', ':' },
  prefixed_priority = 1100,
}
