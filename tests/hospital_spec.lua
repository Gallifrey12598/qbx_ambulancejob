local stubbedCallbacks

local function setup()
  stubbedCallbacks = {}

  package.loaded['config.server'] = {}
  package.loaded['config.shared'] = {
    locations = {
      hospitals = {
        test = { beds = { {}, {}, {} } }
      }
    },
    minForCheckIn = 2,
    checkInCost = 100,
  }
  package.loaded['@qbx_core.modules.hooks'] = function() return true end

  _G.lib = {
    callback = {
      register = function(name, fn) stubbedCallbacks[name] = fn end,
    },
    print = {
      debug = function() end,
      warn = function() end,
      info = function() end,
      error = function() end,
    },
  }
  _G.exports = setmetatable({
    qbx_core = {
      GetDutyCountType = function() return 0 end,
      Notify = function() end,
      GetPlayer = function() return nil end,
    }
  }, { __call = function() end })

  _G.RegisterNetEvent = function() end
  _G.AddEventHandler = function() end
  _G.TriggerClientEvent = function() end
  _G.SetTimeout = function() end
  _G.locale = function(key) return key end
  _G.Player = function() return { state = {} } end
  _G.GetInvokingResource = function() return nil end

  package.loaded['server.hospital'] = nil
  require('server.hospital')

  local cb = stubbedCallbacks['qbx_ambulancejob:server:getOpenBed']
  assert(cb, 'getOpenBed callback not registered')
  local _, getOpenBed = debug.getupvalue(cb, 1)
  local _, beds = debug.getupvalue(getOpenBed, 1)
  return getOpenBed, beds
end

describe('getOpenBed', function()
  it('returns the first free bed', function()
    local getOpenBed, beds = setup()
    assert.is_equal(1, getOpenBed('test'))
    beds.test[1] = true
    assert.is_equal(2, getOpenBed('test'))
  end)

  it('returns nil when all beds are occupied', function()
    local getOpenBed, beds = setup()
    beds.test[1] = true
    beds.test[2] = true
    beds.test[3] = true
    assert.is_nil(getOpenBed('test'))
  end)
end)

