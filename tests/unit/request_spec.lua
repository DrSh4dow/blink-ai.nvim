local request = require("blink-ai.request")

describe("request parser", function()
  it("parses SSE events split across chunks", function()
    local seen = {}
    local parser = request.create_sse_parser(function(data)
      table.insert(seen, data)
    end)

    parser.push("data: {\"a\":")
    parser.push("1}\n\n")

    assert.are.same({ "{\"a\":1}" }, seen)
  end)

  it("parses multiline SSE data blocks", function()
    local seen = {}
    local parser = request.create_sse_parser(function(data)
      table.insert(seen, data)
    end)

    parser.push("data: hello\n")
    parser.push("data: world\n\n")

    assert.are.same({ "hello\nworld" }, seen)
  end)

  it("handles done marker", function()
    local done = 0
    local parser = request.create_sse_parser(nil, function()
      done = done + 1
    end)

    parser.push("data: [DONE]\n\n")
    parser.finish()

    assert.are.equal(1, done)
  end)

  it("parses JSONL data and done marker", function()
    local seen = {}
    local done = 0
    local parser = request.create_jsonl_parser(function(data)
      table.insert(seen, data)
    end, function()
      done = done + 1
    end)

    parser.push("{\"a\":1}\n")
    parser.push("data: {\"b\":2}\n[DONE]\n")

    assert.are.same({ "{\"a\":1}", "{\"b\":2}" }, seen)
    assert.are.equal(1, done)
  end)

  it("ignores SSE comments and flushes trailing event", function()
    local seen = {}
    local parser = request.create_sse_parser(function(data)
      table.insert(seen, data)
    end)

    parser.push(": keepalive\n\n")
    parser.push("data: tail")
    parser.finish()

    assert.are.same({ "tail" }, seen)
  end)

  it("flushes trailing JSONL line without newline", function()
    local seen = {}
    local parser = request.create_jsonl_parser(function(data)
      table.insert(seen, data)
    end)

    parser.push("{\"tail\":true}")
    parser.finish()

    assert.are.same({ "{\"tail\":true}" }, seen)
  end)
end)

describe("request helpers", function()
  it("extracts HTTP status marker and strips it from the payload", function()
    local status, body = request._extract_http_status_marker(
      "data: {\"ok\":true}\n__BLINK_HTTP_STATUS__:400:__BLINK_HTTP_STATUS_END__\n"
    )

    assert.are.equal(400, status)
    assert.are.equal("data: {\"ok\":true}\n\n", body)
  end)

  it("extracts API error messages from JSON response bodies", function()
    local message = request._extract_error_message_from_body(
      "{\"error\":{\"message\":\"temperature is not supported\"}}"
    )

    assert.are.equal("temperature is not supported", message)
  end)

  it("extracts API error messages from SSE payload lines", function()
    local message = request._extract_error_message_from_body(
      "data: {\"type\":\"error\",\"message\":\"quota exceeded\"}\n\n"
    )

    assert.are.equal("quota exceeded", message)
  end)
end)
