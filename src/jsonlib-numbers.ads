--  JSON's number syntax, which is narrower than most people remember.
--
--  The grammar is: an optional minus, then either a single zero or a digit
--  from one to nine followed by digits, then optionally a decimal point and at
--  least one digit, then optionally an exponent with an optional sign and at
--  least one digit. That is all.
--
--  Everything else that looks like a number is not one:
--
--    +1        a leading plus
--    01        a leading zero
--    1.        a point with no digits after it
--    .5        a point with no digits before it
--    1e        an exponent with no digits
--    0x1F      hexadecimal
--    Infinity  a name, however many parsers accept it
--    NaN       likewise
--
--  This is here rather than inside the parser because the document model needs
--  the same answer: a caller handing in a number as text has to be held to the
--  same grammar the parser is, or a document could be built that cannot be
--  written out as JSON.
package Jsonlib.Numbers is

   --  Whether text is a JSON number.
   --
   --  @param Text The text, with no surrounding whitespace.
   --  @return True when it matches the grammar exactly.
   function Is_Valid (Text : String) return Boolean;

   --  Whether a number was written as an integer.
   --
   --  Decided by the text, not by the value: 1.0 and 1e2 are floats even
   --  though both are whole. A configuration that wrote 1.0 means a float, and
   --  a program that rewrote it as 1 would have changed what the file says.
   --
   --  @param Text A number that Is_Valid accepts.
   --  @return True when it has neither a fraction nor an exponent.
   function Is_Integer_Form (Text : String) return Boolean;

   --  Turn a number into a value.
   --
   --  @param Text A number that Is_Valid accepts.
   --  @param Whole The integer value, when the text is an integer form and
   --         fits. Zero otherwise.
   --  @param Real The value as a float, always.
   --  @param Out_Of_Range True when the host cannot represent it. An integer
   --         too large for Long_Long_Integer, or a float that would overflow.
   --         Reported rather than saturated: a value that silently became the
   --         largest representable number is worse than one that was refused,
   --         because nothing downstream can tell it was ever wrong.
   procedure Decode
     (Text         : String;
      Whole        : out Long_Long_Integer;
      Real         : out Long_Float;
      Out_Of_Range : out Boolean);

   --  Ada's image of an integer, without the leading blank Ada puts on
   --  non-negative numbers.
   --
   --  @param Value The value.
   --  @return Its text, which is always a valid JSON number.
   function Image (Value : Long_Long_Integer) return String;

   --  A float as JSON, in a form that reads back as the same value.
   --
   --  Ada's own image is not JSON: it writes 1.00000000000000E+00, which is
   --  legal JSON but unreadable, and for some values it writes forms JSON does
   --  not define. This produces the shortest text that round-trips.
   --
   --  @param Value The value.
   --  @return Its text.
   --  @exception Constraint_Error when Value is not finite. JSON has no way to
   --             write an infinity or a NaN, so a program that produced one and
   --             asked for it to be written has a defect rather than a document.
   function Image (Value : Long_Float) return String;

end Jsonlib.Numbers;
