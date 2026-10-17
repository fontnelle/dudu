# Masks secrets in a text file. Prints the cleaned file to stdout and appends
# "<label>:<line>:<key name>" for every masked secret to the file given in -v logf.
# The value itself is never written anywhere: names are reduced to identifier characters.
# Exits 3 when nothing was masked, so the caller can leave the file untouched.
# Portable across BSD awk, gawk and mawk (no interval expressions). Run with LC_ALL=C.

BEGIN {
  M = "<redacted-by-dudu>"
  # Words that make "<word>...=value" or "<word>...: value" a secret. Matched on lowercase,
  # and only at the start of a name ("db_pass", "PASS=", not "bypass:").
  KEYS = "(authtoken|auth_token|_auth|token|secret|password|passwd|pass|api_key|apikey|api-key|access_key|accesskey|private_key|privatekey|client_secret|credentials|authorization|bearer|cookie)"
  in_pem = 0
  yaml_indent = -1
}

function is_reference(v) {
  # $VAR, "$VAR", ${VAR}, $(cmd): a reference, not a secret
  return v ~ /^["']?\$/
}

function is_plain(v,   t) {
  t = v
  gsub(/["',;]/, "", t)
  gsub(/[ \t]+$/, "", t)
  if (t ~ /^(true|false|yes|no|null|none|nil|on|off)$/) return 1
  # Small numbers are settings (token_limit: 4096); long digit runs may be PINs or keys.
  return t ~ /^[0-9]+$/ && length(t) < 6
}

function clean_name(s) {
  gsub(/[^A-Za-z0-9_.: -]/, "", s)
  if (s == "") s = "secret value"
  return substr(s, 1, 60)
}

# The identifier right before the separator: "export OPENROUTER_API_KEY=" -> OPENROUTER_API_KEY.
# .npmrc "//localhost:4873/:_authToken=" -> "npm token localhost:4873".
function key_name(head,   h) {
  if (head ~ /^\/\/[^\/]+\/.*:_?auth/) {
    h = head
    sub(/^\/\//, "", h)
    sub(/\/.*/, "", h)
    return clean_name("npm token " h)
  }
  if (match(head, /[A-Za-z0-9_.-]+["']?[ \t]*[=:]?[ \t]*$/)) {
    h = substr(head, RSTART, RLENGTH)
    gsub(/["' \t=:]/, "", h)
    return clean_name(h)
  }
  return "secret value"
}

function note(n) {
  hit = 1
  any = 1
  if (logf != "") print label ":" NR ":" clean_name(n) >> logf
}

# Length of the value at the start of v: up to the closing quote, or to a delimiter.
# Header-like keys (Authorization: Bearer x) take the rest of the line.
function value_len(v, whole,   q, i) {
  q = substr(v, 1, 1)
  if (q == "\"" || q == "'") {
    i = index(substr(v, 2), q)
    return i ? i + 1 : length(v)
  }
  if (whole) {
    if (match(v, /["'<]/)) return RSTART - 1
    return length(v)
  }
  if (match(v, /[ \t;,})&|]/)) return RSTART - 1
  return length(v)
}

function masked(v,   q) {
  q = substr(v, 1, 1)
  if (q == "\"" || q == "'") return q M q
  return M
}

# Every "<secret name> = value" and "<secret name>: value" on the line.
function mask_pairs(s,   out, low, rest, head, v, n, kw, whole, b) {
  out = ""
  while (1) {
    low = tolower(s)
    if (!match(low, KEYS "[a-z0-9_.-]*[\"']?[ \t]*[=:][ \t]*")) break
    b = RSTART > 1 ? substr(low, RSTART - 1, 1) : ""
    head = substr(s, 1, RSTART + RLENGTH - 1)
    rest = substr(s, RSTART + RLENGTH)
    if (b ~ /[a-z]/) { out = out head; s = rest; continue }
    kw = substr(low, RSTART, RLENGTH)
    if (rest ~ /^[|>][-+]?[0-9]?[ \t]*$/) { yaml_start = 1; out = out head rest; s = ""; break }
    whole = kw ~ /^(authorization|bearer|cookie)/
    n = value_len(rest, whole)
    v = substr(rest, 1, n)
    if (n > 0 && v !~ /^[ \t]*$/ && !is_reference(v) && !is_plain(v) && index(v, M) == 0) {
      out = out head masked(v)
      note(key_name(head))
    } else {
      out = out head v
    }
    s = substr(rest, n + 1)
  }
  return out s
}

# scheme://user:password@host -> scheme://user:<redacted-by-dudu>@host
function mask_urls(s,   out, seg, p) {
  out = ""
  while (match(s, /[A-Za-z][A-Za-z0-9+.-]*:\/\/[^\/ :@"']+:[^\/ @"']+@/)) {
    seg = substr(s, RSTART, RLENGTH)
    p = index(substr(seg, index(seg, "://") + 3), ":") + index(seg, "://") + 2
    if (substr(seg, p + 1, length(seg) - p - 1) == M || substr(seg, p + 1, 1) == "$") {
      out = out substr(s, 1, RSTART + RLENGTH - 1)
    } else {
      out = out substr(s, 1, RSTART - 1) substr(seg, 1, p) M "@"
      note("password in URL")
    }
    s = substr(s, RSTART + RLENGTH)
  }
  return out s
}

function shape_name(tok) {
  if (tok ~ /^(gh|github_pat_)/) return "GitHub token"
  if (tok ~ /^glpat-/) return "GitLab token"
  if (tok ~ /^xox/) return "Slack token"
  if (tok ~ /^npm_/) return "npm token"
  if (tok ~ /^AKIA/) return "AWS access key"
  if (tok ~ /^AIza/) return "Google API key"
  if (tok ~ /^(sk_live_|rk_live_)/) return "Stripe key"
  if (tok ~ /^hf_/) return "Hugging Face token"
  if (tok ~ /^eyJ/) return "JWT"
  return "API key"
}

# Known token shapes and JWTs, anywhere in the line.
function mask_shapes(s,   out, before, after) {
  out = ""
  while (match(s, /(ghp_|gho_|ghu_|ghs_|ghr_|github_pat_|glpat-|xox[abprs]-|sk-|sk_live_|rk_live_|hf_|xai-|npm_|AKIA|AIza|eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]*\.)[A-Za-z0-9_-]+/)) {
    # A token starts and ends on its own: inside a longer word or a base64 blob (plist
    # <data>, fonts, colors) the same letters are not a key, and masking would corrupt it.
    before = RSTART > 1 ? substr(s, RSTART - 1, 1) : ""
    after = substr(s, RSTART + RLENGTH, 1)
    if (before ~ /[A-Za-z0-9+\/]/ || after ~ /[+\/=]/) {
      out = out substr(s, 1, RSTART + RLENGTH - 1)
    } else if (RLENGTH >= 20) {
      out = out substr(s, 1, RSTART - 1) M
      note(shape_name(substr(s, RSTART, RLENGTH)))
    } else {
      out = out substr(s, 1, RSTART + RLENGTH - 1)
    }
    s = substr(s, RSTART + RLENGTH)
  }
  return out s
}

# fish: set -gx HF_TOKEN value
function mask_fish(s,   low, pre, name, v) {
  if (!match(s, /^[ \t]*set[ \t]+(-[A-Za-z]+[ \t]+)*[A-Za-z_][A-Za-z0-9_]*[ \t]+/)) return s
  pre = substr(s, 1, RLENGTH)
  name = pre
  sub(/[ \t]+$/, "", name)
  sub(/.*[ \t]/, "", name)
  low = "_" tolower(name)
  if (!match(low, "[^a-z]" KEYS)) return s
  v = substr(s, length(pre) + 1)
  if (v == "" || is_reference(v) || is_plain(v) || index(v, M)) return s
  note(name)
  return pre masked(v)
}

function indent_of(s) {
  match(s, /^[ \t]*/)
  return RLENGTH
}

{
  line = $0
  hit = 0

  # PEM private keys: the whole block becomes one masked line.
  if (in_pem) {
    if (line ~ /-----END [A-Z ]*PRIVATE KEY-----/) in_pem = 0
    next
  }
  if (line ~ /-----BEGIN [A-Z ]*PRIVATE KEY-----/) {
    note("private key")
    if (line ~ /-----END [A-Z ]*PRIVATE KEY-----/) {
      sub(/-----BEGIN [A-Z ]*PRIVATE KEY-----.*-----END [A-Z ]*PRIVATE KEY-----/, M, line)
    } else {
      sub(/-----BEGIN [A-Z ]*PRIVATE KEY-----.*/, M, line)
      in_pem = 1
    }
    print line
    next
  }

  # YAML block value under a secret key ("api_key: |"): mask the indented lines below it.
  if (yaml_indent >= 0) {
    if (line ~ /^[ \t]*$/ || indent_of(line) > yaml_indent) {
      if (line !~ /^[ \t]*$/) {
        if (!yaml_noted) { note(yaml_name); yaml_noted = 1 }
        line = substr(line, 1, indent_of(line)) M
      }
      print line
      next
    }
    yaml_indent = -1
  }

  yaml_start = 0
  line = mask_pairs(line)
  if (yaml_start) {
    yaml_indent = indent_of(line)
    yaml_noted = 0
    yaml_name = line
    sub(/[ \t]*[|>][-+]?[0-9]?[ \t]*$/, "", yaml_name)
    yaml_name = key_name(yaml_name)
  }
  line = mask_fish(line)
  line = mask_urls(line)
  line = mask_shapes(line)
  print line
}

END { exit(any ? 0 : 3) }
