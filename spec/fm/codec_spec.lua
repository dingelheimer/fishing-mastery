local addon = require("spec.helpers.addon")

describe("FishingMastery Codec", function()
    local Codec

    local DAY = 20763
    local T0 = DAY * 86400

    before_each(function()
        Codec = addon.load({ "Codec.lua", "CodecDecode.lua" }, nil, "FishingMastery").Codec
    end)

    local function roundTrip(casts)
        local chunks = Codec.Encode(DAY, casts)
        local decoded = {}
        for _, chunk in ipairs(chunks) do
            local day, list = Codec.Decode(chunk)
            assert.are.equal(DAY, day, list)
            for _, cast in ipairs(list) do
                decoded[#decoded + 1] = cast
            end
        end
        return decoded, chunks
    end

    local function catch(t, fields)
        local cast = {
            t = t,
            out = "catch",
            map = 1411,
            sub = 2,
            rank = 11,
            mod = 25,
            lure = 263,
            bite = 157,
            auto = true,
            loot = { { id = 6303, qty = 1, q = 1 } },
            srcType = "GameObject",
            srcId = 35591,
        }
        for key, value in pairs(fields or {}) do
            cast[key] = value
        end
        return cast
    end

    it("round-trips every field of a catch", function()
        local casts = { catch(T0 + 3600) }
        assert.are.same(casts, roundTrip(casts))
    end)

    it("round-trips every outcome, missing fields, and changes back to none", function()
        local casts = {
            catch(T0 + 100),
            { t = T0 + 130, out = "getaway", map = 1411, sub = 2, rank = 11, mod = 25, lure = 263 },
            { t = T0 + 150, out = "early_click", map = 1411, sub = 2, rank = 11, mod = 0 },
            { t = T0 + 160, out = "early_click", click = 42 },
            { t = T0 + 170, out = "getaway", click = 128 },
            { t = T0 + 190, out = "timeout", map = 1454, rank = 12, mod = 0 },
            { t = T0 + 200, out = "cancel", map = 1454, rank = 12, mod = 0 },
            { t = T0 + 210, out = "invalid_target", map = 1454, rank = 12, mod = 0 },
            { t = T0 + 211, out = "unknown" },
            catch(
                T0 + 240,
                { lure = false, mod = 0, auto = false, srcType = false, srcId = false }
            ),
            catch(T0 + 280, { bite = false, loot = {} }),
        }
        -- false marks a field the record does not have.
        for _, cast in ipairs(casts) do
            for key, value in pairs(cast) do
                if value == false and key ~= "auto" then
                    cast[key] = nil
                end
            end
        end
        assert.are.same(casts, roundTrip(casts))
    end)

    it("round-trips several loot slots, missing quality, and other source types", function()
        local casts = {
            catch(T0 + 10, {
                loot = {
                    { id = 6303, qty = 1, q = 1 },
                    { id = 6358, qty = 3 },
                    { id = 21071, qty = 2, q = 2 },
                },
            }),
            catch(T0 + 40, { loot = { { id = 6291, qty = 2 } }, srcType = "Creature", srcId = 7 }),
            catch(T0 + 70, { srcType = "Other", srcId = 1 }),
        }
        assert.are.same(casts, roundTrip(casts))
        local unknown = { catch(T0 + 10, { srcType = "Vehicle" }) }
        assert.are.equal("Other", roundTrip(unknown)[1].srcType)
    end)

    it("leaves repeated values empty and drops trailing empty fields", function()
        local chunks = Codec.Encode(DAY, {
            catch(T0 + 100),
            catch(T0 + 121),
            { t = T0 + 150, out = "getaway", map = 1411, sub = 2, rank = 11, mod = 25, lure = 263 },
            catch(T0 + 170, { loot = { { id = 6358, qty = 1, q = 1 } }, bite = 80 }),
        })
        assert.are.equal(
            DAY .. "|100,1,157,6303,1,1,1411,2,11,25,263,1,35591,1;21,1,157;29,2;20,1,80,6358",
            chunks[1]
        )
    end)

    it("keeps the click time of early clicks and getaways in the time field", function()
        local function failure(t, out, fields)
            local cast = { t = t, out = out, map = 1411, sub = 2, rank = 11, mod = 25, lure = 263 }
            for key, value in pairs(fields) do
                cast[key] = value
            end
            return cast
        end
        local chunks = Codec.Encode(DAY, {
            failure(T0 + 100, "early_click", { click = 42 }),
            catch(T0 + 130),
            failure(T0 + 150, "getaway", { click = 128 }),
            -- Click times on other outcomes and bite times on clicks are not saved.
            failure(T0 + 160, "timeout", { click = 99 }),
            failure(T0 + 170, "early_click", { bite = 99 }),
        })
        local expected = "|100,3,42,,,,1411,2,11,25,263;30,1,157,6303,1,1,,,,,,1,35591,1"
            .. ";20,2,128;10,4;10,3"
        assert.are.equal(DAY .. expected, chunks[1])
        local _, casts = Codec.Decode(chunks[1])
        assert.are.equal(42, casts[1].click)
        assert.is_nil(casts[1].bite)
        assert.are.equal(157, casts[2].bite)
        assert.is_nil(casts[2].click)
        assert.are.equal(128, casts[3].click)
        assert.is_nil(casts[4].click)
        assert.is_nil(casts[5].click)
        assert.is_nil(casts[5].bite)
    end)

    it("keeps negative time steps", function()
        local casts = {
            { t = T0 + 500, out = "cancel" },
            { t = T0 + 498, out = "invalid_target" },
        }
        assert.are.same(casts, roundTrip(casts))
    end)

    it("decodes old chunks without the newer fields", function()
        -- Written before srcType, srcId, auto, extra, and click times existed: they decode as
        -- empty (the getaway has no click time).
        local day, casts = Codec.Decode(DAY .. "|100,1,157,6303,1,1,1411,2,11,25,263;30,2")
        assert.are.equal(DAY, day)
        assert.are.same({
            t = T0 + 100,
            out = "catch",
            bite = 157,
            loot = { { id = 6303, qty = 1, q = 1 } },
            map = 1411,
            sub = 2,
            rank = 11,
            mod = 25,
            lure = 263,
        }, casts[1])
        assert.are.same({
            t = T0 + 130,
            out = "getaway",
            map = 1411,
            sub = 2,
            rank = 11,
            mod = 25,
            lure = 263,
        }, casts[2])
    end)

    it("caps chunks at 4,000 characters and starts each chunk with full values", function()
        local casts = {}
        for i = 1, 2000 do
            casts[i] = catch(T0 + i * 30, { bite = 100 + i % 50 })
        end
        local decoded, chunks = roundTrip(casts)
        assert.is_true(#chunks > 1)
        for _, chunk in ipairs(chunks) do
            assert.is_true(#chunk <= Codec.CHUNK_CAP)
            assert.are.equal(DAY, tonumber(chunk:match("^(%d+)|")))
        end
        assert.truthy(chunks[2]:find("^%d+|%d+,1,%d+,6303,1,1,1411,2,11,25,263,1,35591,1;"))
        assert.are.same(casts, decoded)
    end)

    it("rejects broken chunks with a reason", function()
        local cases = {
            [42] = "not a string",
            ["no header"] = "missing day header",
            [DAY .. "|"] = "empty cast",
            [DAY .. "|10,1;;5,2"] = "empty cast",
            [DAY .. "|x,1"] = "bad number",
            [DAY .. "|10,99"] = "bad outcome",
            [DAY .. "|10,1,1.5"] = "bad number",
            [DAY .. "|10,1,,,,,,,,,,,,,,,9"] = "too many fields",
            [DAY .. "|10,1,157,6303,1,1,,,,,,,,,1:2"] = "bad loot slot",
        }
        for chunk, reason in pairs(cases) do
            local day, err = Codec.Decode(chunk)
            assert.is_nil(day, tostring(chunk))
            assert.truthy(err:find(reason, 1, true), tostring(chunk) .. " -> " .. err)
        end
    end)

    it("treats saved text as data and never runs it", function()
        local ran = false
        _G.__fm_codec_probe = function()
            ran = true
        end
        local day = Codec.Decode(DAY .. "|10,1,__fm_codec_probe()")
        assert.is_nil(day)
        assert.is_false(ran)
        _G.__fm_codec_probe = nil
    end)
end)
