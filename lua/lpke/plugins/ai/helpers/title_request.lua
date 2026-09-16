local M = {}

-- History's request callback can throw on HTTP errors or never return a title.
-- Always finish, including when adapter setup fails or a response has no text.
function M.request(generator, chat, prompt, callback)
  local completed = false
  local function finish(title)
    if completed then
      return
    end
    completed = true
    callback(title)
  end

  local ok, job = pcall(function()
    local adapters = require('codecompanion.adapters')
    local opts = generator.opts.title_generation_opts or {}
    local adapter = adapters.resolve(vim.deepcopy(opts.adapter or chat.adapter))
    if adapter.type ~= 'http' then
      return
    end

    -- Copilot chooses its endpoint/parser from the schema, not the payload.
    if opts.model then
      adapter.schema.model.default = opts.model
      adapters.set_model({ adapter = adapter })
    end
    local settings = require('codecompanion.schema').get_default(adapter)
    adapter = adapter:map_schema_to_params(settings)
    adapter.opts.stream = false

    return require('codecompanion.http').new({ adapter = adapter }):request({
      messages = adapter:map_roles({ { role = 'user', content = prompt } }),
    }, {
      callback = function(err, data, response_adapter)
        if err or (type(data) == 'table' and (data.status or 0) >= 400) then
          return finish(nil)
        end
        if not data then
          return
        end

        -- The inline parser reads text after reasoning blocks in Responses.
        local parsed, result =
          pcall(adapters.call_handler, response_adapter, 'parse_inline', data)
        local title = parsed
            and result
            and result.status == 'success'
            and result.output
          or nil
        finish(type(title) == 'string' and vim.trim(title) or nil)
      end,
      done = function()
        finish(nil)
      end,
    }, { silent = true })
  end)

  if not ok or not job then
    finish(nil)
    return
  end

  -- Copilot rate-limit retries can otherwise leave the title pending for minutes.
  vim.defer_fn(function()
    if not completed then
      finish(nil)
      job:shutdown()
    end
  end, 15000)
  return job
end

return M
