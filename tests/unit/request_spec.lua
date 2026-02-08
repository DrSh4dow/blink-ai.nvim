local request = require("blink-ai.request")

describe("request parser", function()
  it("parses SSE events split across chunks", function()
    local seen = {}
    local parser = request.create_sse_parser(function(data)
      table.insert(seen, data)
    end)

    parser.push('data: {"a":')
    parser.push('1}\n\n')

    assert.are.same({ '{"a":1}' }, seen)
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

    parser.push('{"a":1}\n')
    parser.push('data: {"b":2}\n[DONE]\n')

    assert.are.same({ '{"a":1}', '{"b":2}' }, seen)
    assert.are.equal(1, done)
  end)
end)
