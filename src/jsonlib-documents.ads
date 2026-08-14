private with Ada.Containers.Vectors;
private with Ada.Strings.Unbounded;

--  The value model, and how to build one.
--
--  A document is an arena: every value in it is a `Node`, and a node is an
--  index into the document rather than a pointer into the heap. That choice
--  has consequences worth knowing about, because they are the reason for it:
--
--    * a document is one object with one lifetime. Freeing it frees every
--      value in it, and there is no way to hold a value that outlives the
--      document it came from;
--    * copying a node copies an index, not a subtree, so passing values around
--      while building costs nothing;
--    * a node from one document means something else in another. Using one
--      across documents is a defect and is checked.
--
--  **Order is kept.** Object members come back in the order they were written,
--  and stay in that order when the document is written out. RFC 8259 says an
--  object is unordered, which is a statement about equality, not a licence to
--  shuffle somebody's configuration file when a program rewrites it.
--
--  **Numbers keep their text.** JSON has one number type; Ada has several. A
--  value is classified as an integer or a float by how it was written, and the
--  original text is kept beside the decoded value, so a document that is read
--  and written again is byte for byte the same document.
--
--  **Asking a value for something it is not raises.** That is a defect at the
--  call site, not a fact about the input: a program that asks a number for its
--  string value has a bug, and returning "" would hide it. Input problems come
--  back as Jsonlib.Errors values; program problems raise Kind_Error.
package Jsonlib.Documents is

   --  What a value is.
   --
   --  JSON has one number type and this has two, because Ada does. Which one a
   --  value gets is decided by how it was written -- a fraction or an exponent
   --  makes it a float -- and never by whether the value happens to be whole.
   --  A configuration that wrote 1.0 means a float, and turning it into 1
   --  changes what the file says.
   type Value_Kind is
     (Null_Value,
      Boolean_Value,
      Integer_Value,
      Float_Value,
      String_Value,
      Array_Value,
      Object_Value);

   --  A document, and everything in it.
   type Document is tagged limited private;

   --  One value inside a document.
   type Node is private;

   --  No value: what a lookup returns when there is nothing there.
   --
   --  A distinct absent value rather than an exception, because "this
   --  configuration has no such key" is the ordinary case, not an error.
   No_Node : constant Node;

   --  Raised when a program asks a value for something it is not, or uses a
   --  node with the wrong document. Both are defects at the call site.
   Kind_Error : exception;

   --  @param Item Node to test.
   --  @return True when it refers to a value.
   function Is_Present (Item : Node) return Boolean;

   ---------------------------------------------------------------------
   --  Reading.
   ---------------------------------------------------------------------

   --  The document's top-level value.
   --
   --  @param From Document to read.
   --  @return Its root, or No_Node when nothing has been built yet.
   function Root (From : Document) return Node;

   --  @param From Document the node belongs to.
   --  @param Item Node to inspect.
   --  @return What kind of value it is.
   function Kind (From : Document; Item : Node) return Value_Kind;

   --  @param From Document the node belongs to.
   --  @param Item A Boolean_Value node.
   --  @return Its value.
   function As_Boolean (From : Document; Item : Node) return Boolean;

   --  @param From Document the node belongs to.
   --  @param Item An Integer_Value node.
   --  @return Its value.
   function As_Integer (From : Document; Item : Node) return Long_Long_Integer;

   --  The value as a float, whether it was written as one or not.
   --
   --  Accepts an Integer_Value too, because a program reading a timeout does
   --  not care whether the file said 5 or 5.0, and forcing it to check would
   --  only mean every caller wrote the same two-branch helper.
   --
   --  @param From Document the node belongs to.
   --  @param Item An Integer_Value or Float_Value node.
   --  @return Its value.
   function As_Float (From : Document; Item : Node) return Long_Float;

   --  @param From Document the node belongs to.
   --  @param Item A String_Value node.
   --  @return Its value, decoded, as UTF-8.
   function As_String (From : Document; Item : Node) return String;

   --  A number exactly as it was written.
   --
   --  What makes a read-modify-write of somebody else's file safe: a value the
   --  program did not touch goes back out unchanged, including its exponent
   --  form and its trailing zeros.
   --
   --  @param From Document the node belongs to.
   --  @param Item An Integer_Value or Float_Value node.
   --  @return The original text.
   function Literal (From : Document; Item : Node) return String;

   --  How many elements or members.
   --
   --  @param From Document the node belongs to.
   --  @param Item An Array_Value or Object_Value node.
   --  @return The count.
   function Length (From : Document; Item : Node) return Natural;

   --  One element or member value, by position.
   --
   --  Objects are indexed too, and in the order they were written, because a
   --  program that rewrites a file has to be able to walk it.
   --
   --  @param From Document the node belongs to.
   --  @param Item An Array_Value or Object_Value node.
   --  @param Index Which one, from one.
   --  @return That value, or No_Node when Index is out of range.
   function Element (From : Document; Item : Node; Index : Positive) return Node;

   --  One member's name, by position.
   --
   --  @param From Document the node belongs to.
   --  @param Item An Object_Value node.
   --  @param Index Which member, from one.
   --  @return Its name, or "" when Index is out of range.
   function Name (From : Document; Item : Node; Index : Positive) return String;

   --  One member value, by name.
   --
   --  Looked up by walking the members. Objects in real documents have a
   --  handful of members and an index would cost more to build than it saves;
   --  a document with an object of thousands of members will feel it, and that
   --  is a fair trade for keeping order and duplicates representable.
   --
   --  When a name appears more than once -- which the parser only allows if
   --  the caller asked it to -- this returns the first.
   --
   --  @param From Document the node belongs to.
   --  @param Item An Object_Value node.
   --  @param Named The member name, compared byte for byte after decoding.
   --  @return That value, or No_Node when there is no such member.
   function Member (From : Document; Item : Node; Named : String) return Node;

   --  @param From Document the node belongs to.
   --  @param Item An Object_Value node.
   --  @param Named The member name.
   --  @return True when the object has such a member.
   function Has_Member (From : Document; Item : Node; Named : String)
                        return Boolean;

   ---------------------------------------------------------------------
   --  Building.
   ---------------------------------------------------------------------

   --  Empty the document.
   --
   --  Every node from it becomes meaningless; using one afterwards is a defect
   --  and is caught, because a stale index would otherwise read whatever was
   --  built next.
   --
   --  @param Into Document to empty.
   procedure Clear (Into : in out Document);

   --  @param Into Document to add to.
   --  @return A new null value.
   function New_Null (Into : in out Document) return Node;

   --  @param Into Document to add to.
   --  @param Value The value.
   --  @return A new Boolean value.
   function New_Boolean (Into : in out Document; Value : Boolean) return Node;

   --  @param Into Document to add to.
   --  @param Value The value.
   --  @return A new integer value, whose text is Ada's image of Value without
   --          the leading blank.
   function New_Integer (Into : in out Document; Value : Long_Long_Integer)
                         return Node;

   --  @param Into Document to add to.
   --  @param Value The value.
   --  @return A new float value.
   function New_Float (Into : in out Document; Value : Long_Float) return Node;

   --  A number written exactly as given.
   --
   --  What the parser uses, and what a caller wants when a value has to keep a
   --  particular form -- a version number written as 1.10, say, which is not
   --  the same text as 1.1 even though it is the same quantity.
   --
   --  @param Into Document to add to.
   --  @param Text The number, which must be valid JSON number syntax.
   --  @param Item The new node, meaningful only when this returns True.
   --  @return False when Text is not a JSON number, in which case nothing is
   --          added. A refusal rather than an exception: a caller passing text
   --          through from somewhere else is handling input, not making a
   --          mistake.
   function New_Number (Into : in out Document;
                        Text : String;
                        Item : out Node) return Boolean;

   --  @param Into Document to add to.
   --  @param Value The text, as UTF-8. Escaping happens when it is written
   --         out, not here: a document holds text, not JSON.
   --  @return A new string value.
   function New_String (Into : in out Document; Value : String) return Node;

   --  @param Into Document to add to.
   --  @return A new empty array.
   function New_Array (Into : in out Document) return Node;

   --  @param Into Document to add to.
   --  @return A new empty object.
   function New_Object (Into : in out Document) return Node;

   --  Add an element to the end of an array.
   --
   --  @param Into Document both nodes belong to.
   --  @param To An Array_Value node.
   --  @param Item The value to append.
   procedure Append (Into : in out Document; To : Node; Item : Node);

   --  Add a member to the end of an object.
   --
   --  Appends rather than replacing: an object is allowed to hold a name
   --  twice, because a parser told to keep duplicates has to be able to put
   --  them somewhere. Use Set_Member to replace.
   --
   --  @param Into Document both nodes belong to.
   --  @param To An Object_Value node.
   --  @param Named The member name.
   --  @param Item The value.
   procedure Insert (Into : in out Document;
                     To : Node;
                     Named : String;
                     Item : Node);

   --  Add a member, or replace the first one with that name.
   --
   --  Replacing keeps the member where it was rather than moving it to the
   --  end, so rewriting one value in a file does not reorder it.
   --
   --  @param Into Document both nodes belong to.
   --  @param To An Object_Value node.
   --  @param Named The member name.
   --  @param Item The value.
   procedure Set_Member (Into : in out Document;
                         To : Node;
                         Named : String;
                         Item : Node);

   --  Remove the first member with a name.
   --
   --  @param Into Document to edit.
   --  @param From An Object_Value node.
   --  @param Named The member name.
   --  @return True when a member was removed.
   function Remove_Member (Into : in out Document;
                           From : Node;
                           Named : String) return Boolean;

   --  Make a value the document's root.
   --
   --  @param Into Document to set.
   --  @param Item The value.
   procedure Set_Root (Into : in out Document; Item : Node);

   --  Copy a value, and everything under it, into another document.
   --
   --  Needed because a node is an index: handing one to a different document
   --  would be meaningless, and this is the operation people reach for when
   --  they try.
   --
   --  @param Into Document to copy into.
   --  @param From Document to copy from.
   --  @param Item The value in From.
   --  @return The copy, in Into.
   function Copy (Into : in out Document; From : Document; Item : Node)
                  return Node;

private

   --  Every node in a document is identified by its place in the table. Zero
   --  is "no node", which is why the table is indexed from one.
   type Node is new Natural;

   No_Node : constant Node := 0;

   --  One element of an array, or one member of an object. Arrays leave the
   --  name empty rather than having a second table: the two differ only in
   --  whether the name means anything, and one table means one set of bugs.
   type Child is record
      Name   : Ada.Strings.Unbounded.Unbounded_String;
      Target : Node := No_Node;
   end record;

   package Child_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Child);

   type Node_Record is record
      Kind : Value_Kind := Null_Value;

      --  For Boolean_Value.
      Flag : Boolean := False;

      --  For Integer_Value.
      Whole : Long_Long_Integer := 0;

      --  For Float_Value, and for Integer_Value so As_Float need not convert.
      Real : Long_Float := 0.0;

      --  The decoded text for String_Value; the text as written for the two
      --  number kinds. One field because a node is never both.
      Text : Ada.Strings.Unbounded.Unbounded_String;

      --  For Array_Value and Object_Value.
      Children : Child_Vectors.Vector;
   end record;

   package Node_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Node_Record);

   type Document is tagged limited record
      Nodes : Node_Vectors.Vector;
      Top   : Node := No_Node;
   end record;

end Jsonlib.Documents;
