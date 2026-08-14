with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

package body Jsonlib.Serializers is

   use Ada.Strings.Unbounded;

   package Doc renames Jsonlib.Documents;

   use type Doc.Value_Kind;

   Hex : constant String := "0123456789abcdef";

   ------------
   -- Escape --
   ------------

   function Escape (Item : String; Escape_Non_Ascii : Boolean := False)
                    return String
   is
      Result : Unbounded_String;

      procedure Put_Escape (Code : Natural);

      procedure Put_Escape (Code : Natural) is
      begin
         Append (Result, "\u");
         Append (Result, Hex (Hex'First + (Code / 16#1000#) mod 16));
         Append (Result, Hex (Hex'First + (Code / 16#100#) mod 16));
         Append (Result, Hex (Hex'First + (Code / 16#10#) mod 16));
         Append (Result, Hex (Hex'First + Code mod 16));
      end Put_Escape;

      Index : Natural := Item'First;

   begin
      while Index <= Item'Last loop
         declare
            Byte : constant Natural := Character'Pos (Item (Index));
         begin
            case Item (Index) is
               --  The two that must always be escaped.
               when '"' =>
                  Append (Result, "\""");
                  Index := Index + 1;

               when '\' =>
                  Append (Result, "\\");
                  Index := Index + 1;

               when others =>
                  if Byte < 16#20# then
                     --  Control characters must be escaped. The five with
                     --  short forms get them: a reader looking at the file
                     --  expects a backslash-n, not a six-character escape for
                     --  the commonest character in it.
                     case Byte is
                        when 16#08# => Append (Result, "\b");
                        when 16#09# => Append (Result, "\t");
                        when 16#0A# => Append (Result, "\n");
                        when 16#0C# => Append (Result, "\f");
                        when 16#0D# => Append (Result, "\r");
                        when others => Put_Escape (Byte);
                     end case;

                     Index := Index + 1;

                  elsif Byte < 16#80# then
                     --  Ordinary ASCII, including the solidus. RFC 8259 allows
                     --  \/ and does not require it, and escaping it makes
                     --  every URL in a document harder to read.
                     Append (Result, Item (Index));
                     Index := Index + 1;

                  elsif not Escape_Non_Ascii then
                     --  Already UTF-8, and JSON is UTF-8. Passed through
                     --  byte for byte.
                     Append (Result, Item (Index));
                     Index := Index + 1;

                  else
                     --  Decode the character so it can be written as one or
                     --  two \u escapes. Anything malformed is passed through
                     --  rather than guessed at: this function escapes, it does
                     --  not validate, and silently rewriting a byte would hide
                     --  a problem that belongs to whoever produced the text.
                     declare
                        Needed : Natural;
                        Code   : Natural;
                        Good   : Boolean := True;
                     begin
                        if Byte in 16#C2# .. 16#DF# then
                           Needed := 1;
                           Code := Byte - 16#C0#;
                        elsif Byte in 16#E0# .. 16#EF# then
                           Needed := 2;
                           Code := Byte - 16#E0#;
                        elsif Byte in 16#F0# .. 16#F4# then
                           Needed := 3;
                           Code := Byte - 16#F0#;
                        else
                           Needed := 0;
                           Code := 0;
                           Good := False;
                        end if;

                        for Step in 1 .. Needed loop
                           if Index + Step > Item'Last
                             or else Character'Pos (Item (Index + Step))
                                     not in 16#80# .. 16#BF#
                           then
                              Good := False;
                              exit;
                           end if;

                           Code := Code * 16#40#
                             + (Character'Pos (Item (Index + Step)) - 16#80#);
                        end loop;

                        if not Good then
                           Append (Result, Item (Index));
                           Index := Index + 1;
                        elsif Code < 16#1_0000# then
                           Put_Escape (Code);
                           Index := Index + Needed + 1;
                        else
                           --  Above the basic plane, JSON writes a surrogate
                           --  pair. This is the one place this crate produces
                           --  surrogates, and it produces them only in pairs.
                           Put_Escape
                             (16#D800# + (Code - 16#1_0000#) / 16#400#);
                           Put_Escape
                             (16#DC00# + (Code - 16#1_0000#) mod 16#400#);
                           Index := Index + Needed + 1;
                        end if;
                     end;
                  end if;
            end case;
         end;
      end loop;

      return To_String (Result);
   end Escape;

   --  One container being written, and how far through it we are. An explicit
   --  stack rather than recursion: a document is often something a program was
   --  handed, and a deeply nested one must write out rather than exhaust the
   --  stack. It also means writing has no failure mode at all.
   type Frame is record
      Container : Doc.Node := Doc.No_Node;
      Next      : Natural := 0;

      --  Member positions in the order they will be written. Held per frame
      --  so that Sort_Members does not have to reorder the document itself --
      --  writing must not change what it is writing.
      Order : Natural := 0;
   end record;

   package Frame_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Frame);

   package Index_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Positive);

   package Order_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Index_Vectors.Vector,
      "=" => Index_Vectors."=");

   ---------------
   -- To_String --
   ---------------

   function To_String
     (From     : Jsonlib.Documents.Document;
      Item     : Jsonlib.Documents.Node;
      Settings : Options := Default_Options) return String
   is
      Result : Unbounded_String;
      Stack  : Frame_Vectors.Vector;
      Orders : Order_Vectors.Vector;

      procedure Put_Break;
      procedure Put_Scalar_Or_Open (Value : Doc.Node);
      function Member_Order (Container : Doc.Node) return Index_Vectors.Vector;

      ------------------
      -- Member_Order --
      ------------------

      function Member_Order (Container : Doc.Node) return Index_Vectors.Vector
      is
         Count  : constant Natural := Doc.Length (From, Container);
         Result : Index_Vectors.Vector;
      begin
         for Index in 1 .. Count loop
            Result.Append (Index);
         end loop;

         if not Settings.Sort_Members
           or else Doc.Kind (From, Container) /= Doc.Object_Value
         then
            return Result;
         end if;

         --  Insertion sort, and stable: two members with the same name keep
         --  the order they were written in, which is the only thing that makes
         --  sorted output of a document with duplicates reproducible.
         for Outer in 2 .. Count loop
            declare
               Moving : constant Positive := Result.Element (Outer);
               Name   : constant String := Doc.Name (From, Container, Moving);
               Inner  : Natural := Outer - 1;
            begin
               while Inner >= 1
                 and then Doc.Name (From, Container, Result.Element (Inner))
                          > Name
               loop
                  Result.Replace_Element (Inner + 1, Result.Element (Inner));
                  Inner := Inner - 1;
               end loop;

               Result.Replace_Element (Inner + 1, Moving);
            end;
         end loop;

         return Result;
      end Member_Order;

      ----------------
      -- Put_Break --
      ----------------

      procedure Put_Break is
      begin
         if Settings.Form = Compact then
            return;
         end if;

         Append (Result, Character'Val (16#0A#));

         for Ignored in 1 .. Natural (Stack.Length) * Settings.Indent loop
            Append (Result, ' ');
         end loop;
      end Put_Break;

      -------------------------
      -- Put_Scalar_Or_Open --
      -------------------------

      procedure Put_Scalar_Or_Open (Value : Doc.Node) is
      begin
         case Doc.Kind (From, Value) is
            when Doc.Null_Value =>
               Append (Result, "null");

            when Doc.Boolean_Value =>
               Append (Result,
                       (if Doc.As_Boolean (From, Value) then "true" else "false"));

            when Doc.Integer_Value | Doc.Float_Value =>
               --  The text it was written with, not a fresh image of the
               --  value. This is what makes a read-modify-write of somebody
               --  else's file leave untouched numbers alone.
               Append (Result, Doc.Literal (From, Value));

            when Doc.String_Value =>
               Append (Result, '"');
               Append (Result,
                       Escape (Doc.As_String (From, Value),
                               Settings.Escape_Non_Ascii));
               Append (Result, '"');

            when Doc.Array_Value =>
               Append (Result, '[');
               Stack.Append (Frame'(Container => Value, Next => 0,
                                    Order => Natural (Orders.Length) + 1));
               Orders.Append (Member_Order (Value));

            when Doc.Object_Value =>
               Append (Result, '{');
               Stack.Append (Frame'(Container => Value, Next => 0,
                                    Order => Natural (Orders.Length) + 1));
               Orders.Append (Member_Order (Value));
         end case;
      end Put_Scalar_Or_Open;

   begin
      if not Doc.Is_Present (Item) then
         return "";
      end if;

      Put_Scalar_Or_Open (Item);

      while not Stack.Is_Empty loop
         declare
            Top     : Frame := Stack.Last_Element;
            Count   : constant Natural := Doc.Length (From, Top.Container);
            Is_Object : constant Boolean :=
              Doc.Kind (From, Top.Container) = Doc.Object_Value;
         begin
            if Top.Next >= Count then
               Stack.Delete_Last;

               --  The closing bracket lines up with the line that opened it,
               --  which means one level less indentation than its contents.
               if Count > 0 then
                  Put_Break;
               end if;

               Append (Result, (if Is_Object then '}' else ']'));

            else
               if Top.Next > 0 then
                  Append (Result, ',');
               end if;

               Put_Break;

               declare
                  Position : constant Positive :=
                    Orders.Element (Top.Order).Element (Top.Next + 1);
               begin
                  if Is_Object then
                     Append (Result, '"');
                     Append (Result,
                             Escape (Doc.Name (From, Top.Container, Position),
                                     Settings.Escape_Non_Ascii));
                     Append (Result, '"');
                     Append (Result, ':');

                     if Settings.Form = Pretty then
                        Append (Result, ' ');
                     end if;
                  end if;

                  --  The frame is advanced and stored back *before* the child
                  --  is written, because writing a container pushes a new
                  --  frame and this one must already be pointing past the
                  --  child by the time it comes back.
                  Top.Next := Top.Next + 1;
                  Stack.Replace_Element (Stack.Last_Index, Top);

                  Put_Scalar_Or_Open
                    (Doc.Element (From, Top.Container, Position));
               end;
            end if;
         end;
      end loop;

      return To_String (Result);
   end To_String;

   ---------------
   -- To_String --
   ---------------

   function To_String
     (From     : Jsonlib.Documents.Document;
      Settings : Options := Default_Options) return String
   is
   begin
      return To_String (From, Doc.Root (From), Settings);
   end To_String;

end Jsonlib.Serializers;
