///|
/// A browser-facing shell around the library: plain strings in, a JSON string
/// out, so the page needs to know nothing about MoonBit values.

///|
fn fault_text(f : @idna.Fault) -> String {
  match f {
    Shape(at~) => "label \{at} is not a valid label"
    Hyphen(at~) => "label \{at} breaks the hyphen rules"
    Dot(at~) => "a dot at \{at} is out of place"
    Disallowed(at~, got~) => "'\{got}' at \{at} is not allowed in a host name"
    Std3(at~, got~) => "'\{got}' at \{at} is outside STD3"
    Punycode(at~) => "label \{at} is not valid Punycode"
    Joiner(at~) => "a joiner at \{at} breaks the ContextJ rules"
    Bidi(at~) => "label \{at} breaks the bidi rule"
    Empty(at~) => "label \{at} is empty"
    Length(limit~, got~) => "\{got} octets, over the limit of \{limit}"
  }
}

///|
fn outcome(o : @idna.Outcome) -> Json {
  {
    "name": Json::string(o.name),
    "errors": Json::array(o.errors.map(f => Json::string(fault_text(f)))),
  }
}

///|
/// A host name both ways, UTS 46 processing with its default options.
pub fn idna(name : String) -> String {
  let json : Json = {
    "ascii": outcome(@idna.to_ascii(name)),
    "unicode": outcome(@idna.to_unicode(name)),
  }
  json.stringify()
}

///|
fn text_of(v : Json) -> String {
  match v {
    String(s) => s
    other => other.stringify()
  }
}

///|
/// The variables a JSON object names: a string or number is a value, an array
/// of them a list, an object or an array of pairs a map.
fn variables(v : Json) -> Map[String, @template.Value] raise {
  guard v is Object(members) else { fail("the variables are a JSON object") }
  let out : Map[String, @template.Value] = Map([])
  for name, value in members {
    out[name] = match value {
      Array(items) =>
        if items is [Array(_), ..] {
          Pairs(
            items.map(p => {
              match p {
                Array([k, v, ..]) => (text_of(k), text_of(v))
                other => (text_of(other), "")
              }
            }),
          )
        } else {
          List(items.map(text_of))
        }
      Object(m) => Pairs(m.iter().map(kv => (kv.0, text_of(kv.1))).collect())
      other => Text(text_of(other))
    }
  }
  out
}

///|
fn template_fault(e : @template.Refused) -> String {
  match e {
    Bracket(at~) => "an unclosed brace at \{at}"
    Syntax(at~, got~) => "'\{got}' at \{at} is not allowed in an expression"
    Operator(at~, got~) => "'\{got}' at \{at} is a reserved operator"
    Length(at~, limit~, got~) => "prefix \{got} at \{at} is over \{limit}"
  }
}

///|
/// An RFC 6570 template expanded with the variables in `vars`.
pub fn expand(template : String, vars : String) -> String {
  let refused = (message : String) => {
    let json : Json = { "ok": false, "error": Json::string(message) }
    json.stringify()
  }
  let t = @template.Template::decode(template) catch {
    e => return refused(template_fault(e))
  }
  let values = variables(@json.parse(vars)) catch {
    e => return refused("variables: \{e}")
  }
  let json : Json = { "ok": true, "result": Json::string(t.expand(values)) }
  json.stringify()
}

///|
fn optional(s : String?) -> Json {
  match s {
    Some(v) => Json::string(v)
    None => Json::null()
  }
}

///|
/// A URL taken apart, by RFC 3986 or by the WHATWG standard.
pub fn split(input : String, syntax : String) -> String {
  let grammar : @moonurl.Syntax = if syntax == "whatwg" {
    Whatwg
  } else {
    Rfc3986
  }
  let json : Json = try {
    let u = @moonurl.Url::decode(input, syntax=grammar)
    {
      "ok": true,
      "scheme": optional(u.scheme),
      "userinfo": optional(u.userinfo),
      "host": optional(u.host),
      "port": optional(u.port.map(p => p.to_string())),
      "path": Json::string(u.path),
      "query": optional(u.query),
      "fragment": optional(u.fragment),
      "normalized": Json::string(u.normalize().encode()),
    }
  } catch {
    e => { "ok": false, "error": Json::string(url_fault(e)) }
  }
  json.stringify()
}

///|
fn url_fault(e : @moonurl.Refused) -> String {
  match e {
    Port(at~) => "the port at \{at} is not a number in range"
    Host(at~) => "the host at \{at} is malformed"
    Name(at~) => "the host name at \{at} is not valid"
    Address(at~) => "the IP address at \{at} is malformed"
    Scheme(at~) => "the scheme at \{at} is malformed"
    Pairs(limit~) => "more than \{limit} query pairs"
    Pair(limit~, got~) => "a query pair of \{got} octets, over \{limit}"
  }
}
