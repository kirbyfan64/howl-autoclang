import Matcher from howl.util
import config from howl

clang = bundle_load 'ljclang/clang'

-- Is the chunk typed text?
is_typed = (c) -> c.kind.value == clang.completion_kinds.TypedText

-- Return the entire string *without* the character at index i.
del = (s, i) -> s\sub(1, i-1) .. s\sub i+1, -1

units = {} -- Parsed units.
tab = {} -- A table of the completion placeholders.
prev = {} -- The previous completion.

is_ignored_ext = (file) ->
  for ext in *config.clang_ignored_extensions
    return true if file.extension == ext
  false

complete = (context) =>
  file = context.buffer.file
  return if not config.clang_completion or is_ignored_ext file
  text = context.buffer.text
  compls = nil
  res = {}
  -- This (long) condition checks if the only difference between the current
  -- completion context and the last is that another letter was added to a word.
  -- If so, we can reuse the results of the last completion instead of reparsing
  -- the source file. This adds major speed gains with C++.
  if prev.text and prev.text\len! == text\len!-1 and
    prev.text == del(text, context.pos-1) and
    text\sub(context.pos-2, context.pos-1)\gmatch'%w%w'!
    res = prev.res
  else
    tab = {}
    line = context.buffer.lines\at_pos context.pos -- Line object.
    lineno = line.nr
    colno = context.pos - line.start_pos
    path = file.path
    index = clang.Index 0, config.clang_diagnostics
    unsaved = {[path]: text} -- Unsaved files.
    opts = {clang.TranslationUnit.PrecompiledPreamble} -- Precompile the headers.
    unit = nil
    -- If the unit has already been parsed before, use Clang's reparse function.
    if units[path] and units[path].args == config.clang_arguments
      unit = units[path].unit
      unit\reparse unsaved, opts
    else
      unit = index\parse path, config.clang_arguments, unsaved, opts
      units[path] = {:unit, args: config.clang_arguments}
    compls = unit\complete_at path, lineno, colno, unsaved
    -- The result table and length.
    res = {}
    resl = 0
    for compl in *compls.results
      nchunks = #compl.string.chunks
      for i, c in ipairs compl.string.chunks
        -- If the completion is TypedText and the current word contains it, add it
        -- to the result table.
        if is_typed c
          resl += 1
          res[resl] = c.text
          -- If the placeholder results should be gathered, then do so.
          if config.clang_placeholders and i < nchunks
            -- Get all the text AFTER the current chunk.
            after = {j-i, d.text for j, d in ipairs compl.string.chunks when j > i}
            tab[c.text] = table.concat after -- Save it.
  res.authoritive = true
  -- Reset the previous results list.
  prev.res = res

  prev.text = text
  Matcher(res) context.word_prefix

finish_completion = (completion, context) =>
  if next = tab[completion]
    next_char = next\sub(1, 1)
    is_open = next_char\match'[(<[]'
    -- Don't insert anything is the next character is already there.
    return if is_open and context.buffer\sub(context.pos, context.pos) == next_char

    context.buffer\insert next, context.pos

    -- If the text is (), jump ahead by two.
    return if next\match'^%(%)'
      context.pos+2
    -- If the next character is a bracket, jump ahead.
    elseif is_open
      context.pos+1
    else
      context.pos

->
  {
    :complete
    :finish_completion
  }
