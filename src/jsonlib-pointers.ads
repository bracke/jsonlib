with Jsonlib.Documents;

--  Reaching into a document by path: RFC 6901.
--
--  A pointer is a string of slash-separated tokens: `/servers/0/port` means the
--  member `servers`, then element zero of it, then the member `port`. The empty
--  string means the document itself.
--
--  Two escapes exist because the two characters that would otherwise be
--  ambiguous have to be written somehow: `~1` is a slash and `~0` is a tilde.
--  They are unescaped in that order, and the order matters -- doing it the
--  other way round turns `~01` into a slash instead of into the two characters
--  the author wrote.
--
--  **Array indices are zero-based**, as RFC 6901 says, even though everything
--  else in this crate counts from one. That is the standard's choice, not
--  ours, and quietly making them one-based here would mean pointers written
--  against any other tool silently address the wrong element.
--
--  **A pointer that does not resolve is absence, not an error.** Asking whether
--  a configuration has a value at a path is the ordinary use, and a program
--  that had to catch something to find out "no" would be worse to write and
--  worse to read. A pointer that is *malformed* -- one that does not start with
--  a slash, say -- is a different matter and is reported as such.
package Jsonlib.Pointers is

   --  Whether text is a well-formed pointer.
   --
   --  Separate from resolving, because "you typed the path wrong" and "there is
   --  nothing there" are different things to tell a user, and only the first is
   --  their mistake.
   --
   --  @param Path The pointer.
   --  @return True when it is the empty string, or starts with a slash and
   --          contains no tilde that is not part of ~0 or ~1.
   function Is_Valid (Path : String) return Boolean;

   --  Find the value a pointer names.
   --
   --  @param From The document.
   --  @param Path The pointer.
   --  @return That value, or No_Node when the pointer is malformed or names
   --          nothing. Use Is_Valid first when the difference matters.
   function Resolve
     (From : Jsonlib.Documents.Document;
      Path : String) return Jsonlib.Documents.Node;

   --  Find a value relative to another.
   --
   --  @param From The document.
   --  @param Base Where to start.
   --  @param Path The pointer, relative to Base.
   --  @return That value, or No_Node.
   function Resolve
     (From : Jsonlib.Documents.Document;
      Base : Jsonlib.Documents.Node;
      Path : String) return Jsonlib.Documents.Node;

   --  Turn a member name into a pointer token.
   --
   --  Needed whenever a pointer is built from names that came from data: a
   --  member called `a/b` has to be written `a~1b`, and a program that
   --  concatenated it raw would produce a pointer naming two levels.
   --
   --  @param Name The member name.
   --  @return The token, escaped.
   function Escape_Token (Name : String) return String;

end Jsonlib.Pointers;
