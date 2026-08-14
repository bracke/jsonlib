package body Jsonlib.Errors is

   ----------------
   -- Identifier --
   ----------------

   function Identifier (Code : Error_Code) return String is
   begin
      --  Written out rather than derived from 'Image. A derived name would
      --  change whenever an enumeration literal was renamed, and these are
      --  catalog keys: a consumer's translation would fall back to English
      --  without anything failing to compile.
      case Code is
         when No_Error =>
            return "json.error.none";
         when Unexpected_End =>
            return "json.error.unexpected-end";
         when Unexpected_Character =>
            return "json.error.unexpected-character";
         when Trailing_Content =>
            return "json.error.trailing-content";
         when Empty_Document =>
            return "json.error.empty-document";
         when Unterminated_String =>
            return "json.error.unterminated-string";
         when Invalid_Escape =>
            return "json.error.invalid-escape";
         when Invalid_Unicode_Escape =>
            return "json.error.invalid-unicode-escape";
         when Lone_Surrogate =>
            return "json.error.lone-surrogate";
         when Unescaped_Control_Character =>
            return "json.error.unescaped-control-character";
         when Invalid_Encoding =>
            return "json.error.invalid-encoding";
         when Invalid_Number =>
            return "json.error.invalid-number";
         when Number_Out_Of_Range =>
            return "json.error.number-out-of-range";
         when Invalid_Literal =>
            return "json.error.invalid-literal";
         when Expected_Member_Name =>
            return "json.error.expected-member-name";
         when Expected_Colon =>
            return "json.error.expected-colon";
         when Expected_Comma_Or_End =>
            return "json.error.expected-comma-or-end";
         when Trailing_Comma =>
            return "json.error.trailing-comma";
         when Duplicate_Member =>
            return "json.error.duplicate-member";
         when Depth_Exceeded =>
            return "json.error.depth-exceeded";
         when Document_Too_Large =>
            return "json.error.document-too-large";
      end case;
   end Identifier;

end Jsonlib.Errors;
