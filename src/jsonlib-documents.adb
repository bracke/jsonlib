with Jsonlib.Numbers;

package body Jsonlib.Documents is

   use Ada.Strings.Unbounded;

   --  Every read goes through this. A node from another document, or one left
   --  over from before a Clear, would otherwise index whatever happens to be
   --  in the table now and return a plausible wrong answer -- which is the
   --  failure mode an arena has to be defended against.
   procedure Check (From : Document; Item : Node; Expected : Value_Kind);

   procedure Check_Exists (From : Document; Item : Node);

   ------------------
   -- Check_Exists --
   ------------------

   procedure Check_Exists (From : Document; Item : Node) is
   begin
      if Item = No_Node
        or else Natural (Item) > Natural (From.Nodes.Length)
      then
         raise Kind_Error with "a node that this document does not contain";
      end if;
   end Check_Exists;

   -----------
   -- Check --
   -----------

   procedure Check (From : Document; Item : Node; Expected : Value_Kind) is
   begin
      Check_Exists (From, Item);

      if From.Nodes.Constant_Reference (Positive (Item)).Kind /= Expected then
         raise Kind_Error
           with "asked a " & Value_Kind'Image
                  (From.Nodes.Constant_Reference (Positive (Item)).Kind)
                & " for its " & Value_Kind'Image (Expected);
      end if;
   end Check;

   ----------------
   -- Is_Present --
   ----------------

   function Is_Present (Item : Node) return Boolean is
   begin
      return Item /= No_Node;
   end Is_Present;

   ----------
   -- Root --
   ----------

   function Root (From : Document) return Node is
   begin
      return From.Top;
   end Root;

   ----------
   -- Kind --
   ----------

   function Kind (From : Document; Item : Node) return Value_Kind is
   begin
      Check_Exists (From, Item);
      return From.Nodes.Constant_Reference (Positive (Item)).Kind;
   end Kind;

   ----------------
   -- As_Boolean --
   ----------------

   function As_Boolean (From : Document; Item : Node) return Boolean is
   begin
      Check (From, Item, Boolean_Value);
      return From.Nodes.Constant_Reference (Positive (Item)).Flag;
   end As_Boolean;

   ----------------
   -- As_Integer --
   ----------------

   function As_Integer (From : Document; Item : Node) return Long_Long_Integer
   is
   begin
      Check (From, Item, Integer_Value);
      return From.Nodes.Constant_Reference (Positive (Item)).Whole;
   end As_Integer;

   --------------
   -- As_Float --
   --------------

   function As_Float (From : Document; Item : Node) return Long_Float is
   begin
      Check_Exists (From, Item);

      --  An integer is accepted here on purpose: a program reading a timeout
      --  does not care whether the file said 5 or 5.0, and making it check
      --  would only mean every caller wrote the same two-branch helper.
      case From.Nodes.Constant_Reference (Positive (Item)).Kind is
         when Integer_Value | Float_Value =>
            return From.Nodes.Constant_Reference (Positive (Item)).Real;

         when others =>
            raise Kind_Error
              with "asked a " & Value_Kind'Image
                     (From.Nodes.Constant_Reference (Positive (Item)).Kind)
                   & " for a number";
      end case;
   end As_Float;

   ---------------
   -- As_String --
   ---------------

   function As_String (From : Document; Item : Node) return String is
   begin
      Check (From, Item, String_Value);
      return To_String (From.Nodes.Constant_Reference (Positive (Item)).Text);
   end As_String;

   -------------
   -- Literal --
   -------------

   function Literal (From : Document; Item : Node) return String is
   begin
      Check_Exists (From, Item);

      case From.Nodes.Constant_Reference (Positive (Item)).Kind is
         when Integer_Value | Float_Value =>
            return To_String (From.Nodes.Constant_Reference (Positive (Item)).Text);

         when others =>
            raise Kind_Error with "asked a non-number for its literal";
      end case;
   end Literal;

   ------------
   -- Length --
   ------------

   function Length (From : Document; Item : Node) return Natural is
   begin
      Check_Exists (From, Item);

      case From.Nodes.Constant_Reference (Positive (Item)).Kind is
         when Array_Value | Object_Value =>
            return Natural
              (From.Nodes.Constant_Reference (Positive (Item)).Children.Length);

         when others =>
            raise Kind_Error with "asked a scalar for its length";
      end case;
   end Length;

   -------------
   -- Element --
   -------------

   function Element (From : Document; Item : Node; Index : Positive)
                     return Node
   is
   begin
      Check_Exists (From, Item);

      case From.Nodes.Constant_Reference (Positive (Item)).Kind is
         when Array_Value | Object_Value =>
            if Index > Natural
                 (From.Nodes.Constant_Reference (Positive (Item)).Children.Length)
            then
               --  Out of range is absence, not a defect: walking a document
               --  means asking for positions until there are none.
               return No_Node;
            end if;

            return From.Nodes.Constant_Reference (Positive (Item))
                     .Children.Element (Index).Target;

         when others =>
            raise Kind_Error with "indexed a scalar";
      end case;
   end Element;

   ----------
   -- Name --
   ----------

   function Name (From : Document; Item : Node; Index : Positive)
                  return String
   is
   begin
      Check (From, Item, Object_Value);

      if Index > Natural (From.Nodes.Constant_Reference (Positive (Item)).Children.Length)
      then
         return "";
      end if;

      return To_String
        (From.Nodes.Constant_Reference (Positive (Item)).Children.Element (Index).Name);
   end Name;

   ------------
   -- Member --
   ------------

   function Member (From : Document; Item : Node; Named : String) return Node
   is
   begin
      Check (From, Item, Object_Value);

      for Index in 1 .. Natural
        (From.Nodes.Constant_Reference (Positive (Item)).Children.Length)
      loop
         if To_String
              (From.Nodes.Constant_Reference (Positive (Item))
                 .Children.Element (Index).Name) = Named
         then
            return From.Nodes.Constant_Reference (Positive (Item))
                     .Children.Element (Index).Target;
         end if;
      end loop;

      return No_Node;
   end Member;

   ----------------
   -- Has_Member --
   ----------------

   function Has_Member (From : Document; Item : Node; Named : String)
                        return Boolean
   is
   begin
      return Member (From, Item, Named) /= No_Node;
   end Has_Member;

   -----------
   -- Clear --
   -----------

   procedure Clear (Into : in out Document) is
   begin
      Into.Nodes.Clear;
      Into.Top := No_Node;
   end Clear;

   --  Add a node and give back its identity.
   function Add (Into : in out Document; Item : Node_Record) return Node;

   ---------
   -- Add --
   ---------

   function Add (Into : in out Document; Item : Node_Record) return Node is
   begin
      Into.Nodes.Append (Item);
      return Node (Into.Nodes.Length);
   end Add;

   --------------
   -- New_Null --
   --------------

   function New_Null (Into : in out Document) return Node is
   begin
      return Add (Into, (Kind => Null_Value, others => <>));
   end New_Null;

   -----------------
   -- New_Boolean --
   -----------------

   function New_Boolean (Into : in out Document; Value : Boolean) return Node is
   begin
      return Add (Into, (Kind => Boolean_Value, Flag => Value, others => <>));
   end New_Boolean;

   -----------------
   -- New_Integer --
   -----------------

   function New_Integer (Into : in out Document; Value : Long_Long_Integer)
                         return Node
   is
   begin
      return Add
        (Into,
         (Kind  => Integer_Value,
          Whole => Value,
          Real  => Long_Float (Value),
          Text  => To_Unbounded_String (Jsonlib.Numbers.Image (Value)),
          others => <>));
   end New_Integer;

   ---------------
   -- New_Float --
   ---------------

   function New_Float (Into : in out Document; Value : Long_Float) return Node
   is
   begin
      return Add
        (Into,
         (Kind => Float_Value,
          Real => Value,
          Text => To_Unbounded_String (Jsonlib.Numbers.Image (Value)),
          others => <>));
   end New_Float;

   ----------------
   -- New_Number --
   ----------------

   function New_Number (Into : in out Document;
                        Text : String;
                        Item : out Node) return Boolean
   is
      Whole        : Long_Long_Integer;
      Real         : Long_Float;
      Out_Of_Range : Boolean;
   begin
      Item := No_Node;

      --  Held to the same grammar the parser is. A document that accepted
      --  "+1" here could be built and then not written out as JSON, and the
      --  author would find that out from a consumer rather than from us.
      if not Jsonlib.Numbers.Is_Valid (Text) then
         return False;
      end if;

      Jsonlib.Numbers.Decode (Text, Whole, Real, Out_Of_Range);

      if Out_Of_Range then
         return False;
      end if;

      if Jsonlib.Numbers.Is_Integer_Form (Text) then
         Item := Add
           (Into,
            (Kind  => Integer_Value,
             Whole => Whole,
             Real  => Real,
             Text  => To_Unbounded_String (Text),
             others => <>));
      else
         Item := Add
           (Into,
            (Kind => Float_Value,
             Real => Real,
             Text => To_Unbounded_String (Text),
             others => <>));
      end if;

      return True;
   end New_Number;

   ----------------
   -- New_String --
   ----------------

   function New_String (Into : in out Document; Value : String) return Node is
   begin
      return Add
        (Into,
         (Kind => String_Value,
          Text => To_Unbounded_String (Value),
          others => <>));
   end New_String;

   ---------------
   -- New_Array --
   ---------------

   function New_Array (Into : in out Document) return Node is
   begin
      return Add (Into, (Kind => Array_Value, others => <>));
   end New_Array;

   ----------------
   -- New_Object --
   ----------------

   function New_Object (Into : in out Document) return Node is
   begin
      return Add (Into, (Kind => Object_Value, others => <>));
   end New_Object;

   ------------
   -- Append --
   ------------

   procedure Append (Into : in out Document; To : Node; Item : Node) is
      Container : Node_Record;
   begin
      Check (Into, To, Array_Value);
      Check_Exists (Into, Item);

      Container := Into.Nodes.Element (Positive (To));
      Container.Children.Append
        (Child'(Name => Null_Unbounded_String, Target => Item));
      Into.Nodes.Replace_Element (Positive (To), Container);
   end Append;

   ------------
   -- Insert --
   ------------

   procedure Insert (Into : in out Document;
                     To : Node;
                     Named : String;
                     Item : Node)
   is
      Container : Node_Record;
   begin
      Check (Into, To, Object_Value);
      Check_Exists (Into, Item);

      Container := Into.Nodes.Element (Positive (To));
      Container.Children.Append
        (Child'(Name => To_Unbounded_String (Named), Target => Item));
      Into.Nodes.Replace_Element (Positive (To), Container);
   end Insert;

   ----------------
   -- Set_Member --
   ----------------

   procedure Set_Member (Into : in out Document;
                         To : Node;
                         Named : String;
                         Item : Node)
   is
      Container : Node_Record;
   begin
      Check (Into, To, Object_Value);
      Check_Exists (Into, Item);

      Container := Into.Nodes.Element (Positive (To));

      for Index in 1 .. Natural (Container.Children.Length) loop
         if To_String (Container.Children.Element (Index).Name) = Named then
            --  Replaced where it stands rather than moved to the end, so
            --  rewriting one value in a file does not reorder it.
            Container.Children.Replace_Element
              (Index,
               Child'(Name => To_Unbounded_String (Named), Target => Item));
            Into.Nodes.Replace_Element (Positive (To), Container);
            return;
         end if;
      end loop;

      Container.Children.Append
        (Child'(Name => To_Unbounded_String (Named), Target => Item));
      Into.Nodes.Replace_Element (Positive (To), Container);
   end Set_Member;

   -------------------
   -- Remove_Member --
   -------------------

   function Remove_Member (Into : in out Document;
                           From : Node;
                           Named : String) return Boolean
   is
      Container : Node_Record;
   begin
      Check (Into, From, Object_Value);

      Container := Into.Nodes.Element (Positive (From));

      for Index in 1 .. Natural (Container.Children.Length) loop
         if To_String (Container.Children.Element (Index).Name) = Named then
            Container.Children.Delete (Index);
            Into.Nodes.Replace_Element (Positive (From), Container);
            return True;
         end if;
      end loop;

      return False;
   end Remove_Member;

   --------------
   -- Set_Root --
   --------------

   procedure Set_Root (Into : in out Document; Item : Node) is
   begin
      Check_Exists (Into, Item);
      Into.Top := Item;
   end Set_Root;

   ----------
   -- Copy --
   ----------

   function Copy (Into : in out Document; From : Document; Item : Node)
                  return Node
   is
      Source : Node_Record;
      Result : Node;
   begin
      Check_Exists (From, Item);

      Source := From.Nodes.Element (Positive (Item));

      case Source.Kind is
         when Null_Value | Boolean_Value | Integer_Value | Float_Value
            | String_Value =>
            --  A scalar carries no children, so it copies whole -- including
            --  the number's original text, which is the point of keeping it.
            return Add (Into, (Kind   => Source.Kind,
                               Flag   => Source.Flag,
                               Whole  => Source.Whole,
                               Real   => Source.Real,
                               Text   => Source.Text,
                               others => <>));

         when Array_Value =>
            Result := New_Array (Into);

         when Object_Value =>
            Result := New_Object (Into);
      end case;

      --  Depth-first, and recursive: a document built by the parser is
      --  depth-limited, and one built by hand is the caller's own shape.
      for Index in 1 .. Natural (Source.Children.Length) loop
         declare
            Entry_Item : constant Child := Source.Children.Element (Index);
            Copied     : constant Node := Copy (Into, From, Entry_Item.Target);
         begin
            if Source.Kind = Array_Value then
               Append (Into, Result, Copied);
            else
               Insert (Into, Result, To_String (Entry_Item.Name), Copied);
            end if;
         end;
      end loop;

      return Result;
   end Copy;

end Jsonlib.Documents;
