-----------------------------------------
-- SISTEMA DE LOG EM ARQUIVO .TXT
-----------------------------------------

local logfile = io.open("script_log.txt", "w")  -- sobrescreve ao iniciar
-- Se quiser acrescentar sem apagar:
-- local logfile = io.open("script_log.txt", "a")

local function log(msg)
    local frame = emu.framecount()

    -- timestamp do sistema (HH:MM:SS.mmm se suportado)
    local t = os.date("%H:%M:%S")

    local line = string.format("[FRAME %d | %s] %s", frame, t, msg)

    logfile:write(line .. "\n")
    logfile:flush()
    print(line)
end
	


-----------------------------------------
-- ENDEREÇOS (KOF 2002 / NeoGeo)
-----------------------------------------
local timer_addr = 0x10A7D2
local hp1_addr   = 0x108239
local hp2_addr   = 0x108439
local FRAME_RATE = 60

-----------------------------------------
-- DETECTOR DE RESET MANUAL (RESET FÍSICO)
-----------------------------------------
local base_addr = 0x100000
local size = 0x10
local last = {}

for i = 0, size-1 do
    last[i] = memory.readbyte(base_addr + i)
end

local function detect_reset()
    for i = 0, size-1 do
        local now = memory.readbyte(base_addr + i)

        if now ~= last[i] then
            log(">>> RESET MANUAL DETECTADO!")

            aguardando_pre_round = true
            aguardando_inicio = false
            round_ativo = false

            p1_rounds = 0
            p2_rounds = 0

            log("[RESET] Placar zerado!")

            for j = 0, size-1 do
                last[j] = memory.readbyte(base_addr + j)
            end
            return
        end
    end
end

emu.registerafter(detect_reset)

-----------------------------------------
-- VARIÁVEIS PRINCIPAIS DO SISTEMA DE ROUND
-----------------------------------------
aguardando_pre_round = true
aguardando_inicio = false
round_ativo = false
local input_buffer = {}
local gravando_input = false

local hp1_last = memory.readbyte(hp1_addr)
local hp2_last = memory.readbyte(hp2_addr)

p1_rounds = 0
p2_rounds = 0
local frame_counter = 0

-- Controle do RESET automático
local auto_reset_pending = false
local auto_reset_frames = 0
local RESET_DELAY_FRAMES = 300 -- 5 segundos


log("=== SCRIPT FINAL: PARTIDAS + EXTRA ROUND + RESET AUTO + START/COIN ===")

-----------------------------------------
-- ROUND DECISIVO
-----------------------------------------
local function empate_em_ultima_partida()
    return p1_rounds == 2 and p2_rounds == 2
end

-----------------------------------------
-- FUNÇÃO: CHECAR VITÓRIA DA PARTIDA + RESET AUTOMÁTICO
-----------------------------------------
local function checar_vitoria_partida()
    if p1_rounds >= 3 then
        log("#############################")
        log("### PLAYER 1 VENCEU A PARTIDA! ###")
        log("#############################")

        p1_rounds = 0
        p2_rounds = 0

     auto_reset_pending = true
     auto_reset_frames = -RESET_DELAY_FRAMES
        return
    end

    if p2_rounds >= 3 then
        log("#############################")
        log("### PLAYER 2 VENCEU A PARTIDA! ###")
        log("#############################")

        p1_rounds = 0
        p2_rounds = 0

       auto_reset_pending = true
       auto_reset_frames = -RESET_DELAY_FRAMES
        return
    end
end

-----------------------------------------
-- DETECTOR DE START + COIN (SCRIPT 2)
-----------------------------------------
local LENIENCY = 10  

local last_start = {P1=false, P2=false}
local count_start = {P1=0, P2=0}
local frame_start = {P1=0, P2=0}

local last_coin = {P1=false, P2=false}
local count_coin = {P1=0, P2=0}
local frame_coin = {P1=0, P2=0}

local function print_count(prefix, player, cnt)
    local msg = prefix .. " " .. player .. " "

    if     cnt == 1 then msg = msg .. "1x"
    elseif cnt == 2 then msg = msg .. "2x"
    elseif cnt == 3 then msg = msg .. "3x"
    else               msg = msg .. "4x+" end

    log(msg)
end


emu.registerbefore(function()
    local f = emu.framecount()
    local i = joypad.get()

    for _, p in ipairs({"P1","P2"}) do
        local coin_pressed  = i[p.." Coin"] or false
        local start_pressed = i[p.." Start"] or false

        if start_pressed and not last_start[p] then
            frame_start[p] = f
            count_start[p] = count_start[p] + 1
        end
        if (not start_pressed) and last_start[p] then
            if f - frame_start[p] <= LENIENCY then
                print_count("START", p, count_start[p])
                count_start[p] = 0
            end
        end
        last_start[p] = start_pressed

        if coin_pressed and not last_coin[p] then
            frame_coin[p] = f
            count_coin[p] = count_coin[p] + 1
        end
        if (not coin_pressed) and last_coin[p] then
            if f - frame_coin[p] <= LENIENCY then
                print_count("COIN", p, count_coin[p])
                count_coin[p] = 0
            end
        end
        last_coin[p] = coin_pressed
    end
end)

log("Start + Coin Detector carregado.")
-----------------------------------------
-- CAPTURA DE INPUT (FRAME EXATO)
-----------------------------------------
local function capturar_input()
    if not gravando_input then return end

    local f = emu.framecount()
    local i = joypad.get()

    input_buffer[#input_buffer + 1] = {
        frame = f,
        P1 = {
            Up    = i["P1 Up"] or false,
            Down  = i["P1 Down"] or false,
            Left  = i["P1 Left"] or false,
            Right = i["P1 Right"] or false,
            A     = i["P1 Button 1"] or false,
            B     = i["P1 Button 2"] or false,
            C     = i["P1 Button 3"] or false,
            D     = i["P1 Button 4"] or false,
            Start = i["P1 Start"] or false,
            Coin  = i["P1 Coin"] or false,
        },
        P2 = {
            Up    = i["P2 Up"] or false,
            Down  = i["P2 Down"] or false,
            Left  = i["P2 Left"] or false,
            Right = i["P2 Right"] or false,
            A     = i["P2 Button 1"] or false,
            B     = i["P2 Button 2"] or false,
            C     = i["P2 Button 3"] or false,
            D     = i["P2 Button 4"] or false,
            Start = i["P2 Start"] or false,
            Coin  = i["P2 Coin"] or false,
        }
    }
end
-----------------------------------------
-- SALVAR INPUT DO ROUND NO LOG
-----------------------------------------
local function salvar_input_round()
    if #input_buffer == 0 then return end

    logfile:write("----- INPUT ROUND START -----\n")

    for _, e in ipairs(input_buffer) do
        local function b(v) return v and "1" or "0" end

        logfile:write(string.format(
            "F:%d | P1:%s%s%s%s %s%s%s%s S:%s C:%s | P2:%s%s%s%s %s%s%s%s S:%s C:%s\n",
            e.frame,
            b(e.P1.Up), b(e.P1.Down), b(e.P1.Left), b(e.P1.Right),
            b(e.P1.A),  b(e.P1.B),    b(e.P1.C),    b(e.P1.D),
            b(e.P1.Start), b(e.P1.Coin),
            b(e.P2.Up), b(e.P2.Down), b(e.P2.Left), b(e.P2.Right),
            b(e.P2.A),  b(e.P2.B),    b(e.P2.C),    b(e.P2.D),
            b(e.P2.Start), b(e.P2.Coin)
        ))
    end

    logfile:write("----- INPUT ROUND END -----\n")
    logfile:flush()

    input_buffer = {}
end

-----------------------------------------
-- RESET AUTOMÁTICO APÓS PARTIDA ENCERRADA
-----------------------------------------
emu.registerafter(function()
    if not auto_reset_pending then return end

    auto_reset_frames = auto_reset_frames + 1
	if auto_reset_frames < 0 then return end

    -- Pressiona RESET por 2 frames
    if auto_reset_frames <= 2 then
        joypad.set({ ["Reset"] = true })
        if auto_reset_frames == 1 then
            log("[AUTO RESET] Pressionando RESET...")
        end
        return
    end

    -- Solta RESET no 3º frame
    if auto_reset_frames == 3 then
        joypad.set({ ["Reset"] = false })
        auto_reset_pending = false
        log("[AUTO RESET] Reset concluído!")
    end
end)

-----------------------------------------
-- LOOP PRINCIPAL DE ROUND / PARTIDA
-----------------------------------------
while true do
    frame_counter = frame_counter + 1

    local timer_frames = memory.readword(timer_addr)
    local timer_seconds = math.floor(timer_frames / FRAME_RATE)
    local hp1 = memory.readbyte(hp1_addr)
    local hp2 = memory.readbyte(hp2_addr)
	
	capturar_input()


    gui.text(10, 10, "Script ativo")
    gui.text(10, 220, "P1 Rounds: " .. p1_rounds)
    gui.text(10, 235, "P2 Rounds: " .. p2_rounds)

    -- INÍCIO DO ROUND
    if aguardando_pre_round and timer_seconds == 410 then
        aguardando_pre_round = false
        aguardando_inicio = true
    end

    if aguardando_inicio and timer_seconds < 410 then
        log("- ROUND INICIOU -")
        aguardando_inicio = false
        round_ativo = true
		
		input_buffer = {}
        gravando_input = true
		
        hp1_last = hp1
        hp2_last = hp2
    end

    if round_ativo then

        if hp1 ~= hp1_last then
    log("P1 HP: " .. hp1_last .. " -> " .. hp1)
    hp1_last = hp1
end

if hp2 ~= hp2_last then
    log("P2 HP: " .. hp2_last .. " -> " .. hp2)
    hp2_last = hp2
end


        local hp1_morreu = hp1 > 200
        local hp2_morreu = hp2 > 200

        -----------------------------------------------------
        -- KO
        -----------------------------------------------------
        if hp1_morreu or hp2_morreu then
            log("=== ROUND ACABOU (KO) ===")

            if hp1_morreu and hp2_morreu then
                log("EMPATE POR HIT")

                if empate_em_ultima_partida() then
                    log("Round extra criado!")
                else
                    p1_rounds = p1_rounds + 1
                    p2_rounds = p2_rounds + 1
                end

            elseif hp1_morreu then
                log("P2 venceu")
                p2_rounds = p2_rounds + 1

            elseif hp2_morreu then
                log("P1 venceu")
                p1_rounds = p1_rounds + 1
            end

            round_ativo = false
gravando_input = false
salvar_input_round()
aguardando_pre_round = true
checar_vitoria_partida()

        end

        -----------------------------------------------------
        -- TIME OVER
        -----------------------------------------------------
        if timer_seconds == 0 then
            log("=== ROUND ACABOU (TIME OVER) ===")

            if hp1 > hp2 then
                log("P1 venceu (tempo)")
                p1_rounds = p1_rounds + 1

            elseif hp2 > hp1 then
                log("P2 venceu (tempo)")
                p2_rounds = p2_rounds + 1

            else
                log("EMPATE POR TEMPO")

                if empate_em_ultima_partida() then
                    log("Round extra obrigatório!")
                else
                    p1_rounds = p1_rounds + 1
                    p2_rounds = p2_rounds + 1
                end
            end
round_ativo = false
gravando_input = false
salvar_input_round()
aguardando_pre_round = true
checar_vitoria_partida()

        end
    end

    emu.frameadvance()
end
