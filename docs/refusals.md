# Refusals

Every way `jsonlib` can refuse a document, by code.

A refusal is **not an exception**. A document that does not parse is a fact
about the input rather than a defect in the program, so it comes back as a
value carrying a code, a line and a column, and the caller decides what that
means. Exceptions are kept for the program being wrong — asking a number for
its string value — which is a bug at the call site and should stop.

There are 21 codes, and this table is checked against
`src/jsonlib-errors.ads` by `check_jsonlib`: a code added there without a row
here fails the release gate, and a row here naming a code that no longer exists
fails it too.

| Code | Means |
|---|---|
| `No_Error` | Nothing went wrong. Present so a result value is always meaningful, and so a caller that checks the code rather than a separate Boolean is not writing a bug. |
| `Unexpected_End` | The document ended in the middle of something. |
| `Unexpected_Character` | A byte that cannot start any value here. |
| `Trailing_Content` | Text after the end of the top-level value. A second document concatenated to the first is the usual cause, and silently ignoring it would mean reading half of somebody's file. |
| `Empty_Document` | The document contained nothing at all. |
| `Unterminated_String` | A string was not closed before the line or the document ended. |
| `Invalid_Escape` | A backslash followed by something that is not an escape. |
| `Invalid_Unicode_Escape` | A \u escape whose four digits are not four hexadecimal digits. |
| `Lone_Surrogate` | A \u escape naming half of a surrogate pair with no matching half. Refused rather than replaced: a lone surrogate cannot be encoded as UTF-8, and substituting a replacement character would corrupt the document silently. |
| `Unescaped_Control_Character` | A control character written literally inside a string. RFC 8259 requires these to be escaped, and passing one through would produce a document other parsers reject. |
| `Invalid_Encoding` | Bytes that are not valid UTF-8. |
| `Invalid_Number` | A number written in a form JSON does not define: a leading zero, a leading plus, a bare decimal point, a missing exponent digit, or one of the names some parsers accept and the standard does not. |
| `Number_Out_Of_Range` | A number too large for this host's integer or float type. Reported rather than saturated: a configuration value that silently became the largest representable number is worse than one that was refused. |
| `Invalid_Literal` | A literal that begins like true, false or null and is not one. |
| `Expected_Member_Name` | An object member with no name, or a name that is not a string. |
| `Expected_Colon` | A colon was expected between a member name and its value. |
| `Expected_Comma_Or_End` | A comma or a closing bracket was expected. |
| `Trailing_Comma` | A comma with nothing after it. Trailing commas are not JSON, however many parsers allow them. |
| `Duplicate_Member` | The same name twice in one object, where the caller asked for that to be refused. RFC 8259 leaves it undefined, which is precisely why a caller has to be able to say what it means. |
| `Depth_Exceeded` | Nesting deeper than the limit the caller set. A bound exists because a document is often something a program was handed rather than something it wrote, and unbounded nesting is unbounded recursion. |
| `Document_Too_Large` | The document was longer than the caller allowed. |

## Why a refusal carries a position

A parser that answers "invalid JSON" tells the author to read the whole file
again. The line and column are what turn that into a place to look, and they
are counted in characters rather than bytes so that a document containing
multi-byte text points where a reader's editor points.

## What is deliberately not here

There is no code for "accepted with a warning", because nothing is accepted
with a warning: the document either is RFC 8259 or it is refused. There is no
lenient mode, no comment support and no trailing-comma tolerance — a parser
that quietly accepts more than the standard produces documents other tools
reject, and its author finds out from somebody else's error message.
