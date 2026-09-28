-- KS_PTBR_Injetor.lua
-- Injeção Refinada v1.3 Estável (Inclusão de Residentes, Painel do Squad e Log de Chat)

local function InjetorTraducaoKnox()
    print("=== [KNOX PT-BR] Aplicando Injeção Completa v1.3 ===")

    -- 1. CATÁLOGO DE ORDENS
    if KnoxOrderCatalog and not KnoxOrderCatalog.ptBrPatched then
        local catalogTranslations = {
            ["follow"] = "Seguir",
            ["hold"] = "Manter Posi\195\167\195\163o",
            ["relax"] = "Relaxar e Recuperar",
            ["go_to"] = "Ir Para o Local",
            ["guard"] = "Guardar Local",
            ["patrol_area"] = "Patrulhar \195\129rea",
            ["exit_vehicle"] = "Sair do Ve\195\173culo",
            ["enter_vehicle"] = "Entrar no Ve\195\173culo",
            ["drive_ahead"] = "Assumir o Banco do Motorista e Dirigir",
            ["loot_area"] = "Explorar e Procurar",
            ["loot_corpses"] = "Saquear Cad\195\161veres",
            ["loot_building"] = "Saquear Edif\195\173cio",
            ["find_food"] = "Procurar Comida",
            ["find_water"] = "Procurar \195\129gua",
            ["find_medical"] = "Procurar Suprimentos M\195\169dicos",
            ["find_weapon"] = "Procurar Arma Melhor",
            ["find_tools"] = "Procurar Ferramentas \195\186teis",
            ["clean_inventory"] = "Limpar Invent\195\161rio",
            ["return_to_base"] = "Retornar \195\160 Base",
            ["resume_normal_duty"] = "Retomar Rotina Normal",
            ["dismiss"] = "Dispensar",
        }

        local oldCatalogLabel = KnoxOrderCatalog.label
        KnoxOrderCatalog.label = function(key, fallback)
            if key and catalogTranslations[key] then
                return catalogTranslations[key]
            end
            return oldCatalogLabel(key, fallback)
        end
        KnoxOrderCatalog.ptBrPatched = true
    end

    -- 2. INTERFACE, PAINEL DE GERENCIAMENTO, SQUAD E LOGS DE CHAT
    if KnoxBaseManager then
        local uiReplacements = {
            -- A. Instruções e Avisos
            ["No active trips. Give work orders from Residents or a survivor's Orders menu."] = "Sem viagens ativas. Ordene em 'Residentes' ou 'Ordens'.",
            ["No active trips. Give work orders in Residents tab or Survivor Orders menu."] = "Sem viagens ativas. Ordene em 'Residentes' ou 'Ordens'.",
            ["No work areas: choose a type, click Add Area and drag rectangle"] = "Sem \195\161reas: escolha o tipo, clique em Adicionar e arraste.",
            ["No queued work: mark work areas"] = "Sem tarefas na fila: marque \195\161reas de trabalho.",
            ["Assign storage: right-click a container at home > Use for..."] = "Atribuir armazenamento: clique com o bot\195\163o direito em um cont\195\170iner na base > Usar para...",
            ["Assign storage: right-click a container at home > Use for ..."] = "Atribuir armazenamento: clique com o bot\195\163o direito em um cont\195\170iner na base > Usar para...",
            ["Right-click a container at home > Use for Food, Tools, ..."] = "Bot\195\163o direito no cont\195\170iner > Usar p/ Comida, Ferramentas...",
            ["No supplies in Loaded containers"] = "Sem itens nos cont\195\170ineres da base.",
            ["No supplies in loaded containers"] = "Sem itens nos cont\195\170ineres da base.",

            -- B. Rótulos, Botões e Status Rápidos
            ["Workforce:"] = "For\195\167a de Trabalho:",
            ["Workforce"] = "For\195\167a de Trabalho",
            ["Work force"] = "For\195\167a de Trabalho",
            ["Remove Selected"] = "Remover",
            ["Send Party Home"] = "Enviar p/ Casa",
            ["Send Group to Hunt"] = "Enviar p/ Ca\195\167a",
            ["Edit Boundary"] = "Editar Limite",
            ["Show Highlights"] = "Exibir Destaques",
            ["Cancel Selected"] = "Cancelar",
            ["Resume Selected"] = "Retomar",
            ["Reassign Selected"] = "Reatribuir",
            ["HOLD"] = "MANTER POSI\195\135\195\131O",
            ["RELAX"] = "RELAXAR",
            ["FOLLOW"] = "SEGUIR",

            -- C. Aba Residentes (Status / Ações)
            ["Holding here"] = "Esperando aqui",
            ["Waiting here"] = "Esperando aqui",
            ["Moving to location"] = "Indo at\195\169 o local",
            ["Guarding location"] = "Guardando o local",
            ["Looting marked area"] = "Saqueando \195\161rea marcada",
            ["Searching nearby bodies"] = "Revistando corpos pr\195\173ximos",
            ["Looting marked building"] = "Saqueando edif\195\173cio marcado",
            ["Find Better Weapon"] = "Procurar arma melhor",

            -- D. Abas e Cabeçalhos
            ["Base"] = "Base",
            ["Residents"] = "Residentes",
            ["Work"] = "Trabalho",
            ["Away"] = "Ausente",
            ["Factions"] = "Fac\195\167\195\181es",
            ["Job:"] = "Ocupa\195\167\195\163o:",

            -- E. Ocupações e Trabalhos
            ["Ocupa\195\167\195\163o: Farming"] = "Ocupa\195\167\195\163o: Cultivar",
            ["Ocupa\195\167\195\163o: Woodwork"] = "Ocupa\195\167\195\163o: Marcenaria",
            ["Ocupa\195\167\195\163o: Cooking"] = "Ocupa\195\167\195\163o: Cozinhar",
            ["Ocupa\195\167\195\163o: Repair"] = "Ocupa\195\167\195\163o: Reparar",
            ["Ocupa\195\167\195\163o: Barricade Windows"] = "Ocupa\195\167\195\163o: Barricar Janelas",
            ["Ocupa\195\167\195\163o: Rest / Recover"] = "Ocupa\195\167\195\163o: Descansar / Recuperar",
            ["Farming"] = "Cultivar",
            ["Woodwork"] = "Marcenaria",
            ["Cooking"] = "Cozinhar",
            ["Repair"] = "Reparar",
            ["Barricade Windows"] = "Barricar Janelas",
            ["Rest / Recover"] = "Descansar / Recuperar",
            ["Job: Automatic"] = "Ocupa\195\167\195\163o: Autom\195\161tico",
            ["Automatic"] = "Autom\195\161tico",
            ["Now: Patrol"] = "Agora: Patrulhar",
            ["Now: Idle"] = "Agora: Ocioso",
            ["Now:"] = "Agora:",
            ["Move Corpses"] = "Mover Cad\195\161veres",

            -- F. Status dos Sobreviventes e Cartões
            ["Taking a moment"] = "Descansando",
            ["Resting a Moment"] = "Descansando",
            ["On the move"] = "Em tr\195\162nsito",
            ["On the Move"] = "Em tr\195\162nsito",
            ["Fighting"] = "Em Combate",
            ["Travelling"] = "Viajando",
            ["Traveling"] = "Viajando",
            ["with group"] = "com grupo",
            ["Waiting for group"] = "Aguardando grupo",
            ["Regrouping"] = "Reagrupando",
            ["Storing supplies"] = "Guardando suprimentos",
            ["Looking for supplies"] = "Procurando Suprimentos",
            ["Preparing bandages"] = "Preparando Ataduras",
            ["Treating wounds"] = "Tratando Ferimentos",
            ["Returning a book"] = "Devolvendo Livro",
            ["Staying nearby"] = "Permanecendo Perto",
            ["Sorting inventory"] = "Organizando Invent\195\161rio",
            ["Busy"] = "Ocupado(a)",
            ["Faction survivor"] = "Sobrevivente de Fac\195\167\195\163o",
            ["Companion"] = "Companheiro",
            ["Following"] = "Seguindo",
            ["loaded"] = "Carregado",
            ["Loaded"] = "Carregado",
            ["stored"] = "Descarregado",
			["Exploring"] = "Explorando",
			["Exploring"] = "Vasculhando",
            ["Independent"] = "Independente",
            ["Dead"] = "Morto(a)",
            ["dead"] = "morto(a)",
            ["On a mission"] = "Em Miss\195\163o",
            ["At shelter"] = "No Abrigo",
            ["Collecting a book"] = "Coletando Livro",
            ["Idle"] = "Ocioso",
            ["At base"] = "Na base",
            ["Living at base"] = "Morando na base",
            ["Base resident"] = "Residente da base",
            ["Patrolling"] = "Patrulhando",
            ["Patrol"] = "Patrulha",
            ["Checking a building"] = "Verificando edifica\195\167\195\163o",
            ["Returning to base"] = "Retornando \195\160 base",
            ["Reading"] = "Lendo",
            ["Walking around base"] = "Andando pela base",
            ["Keeping watch"] = "Vigiando",
            ["route"] = "rota",
            ["priority"] = "prioridade",
            ["NPC faction"] = "Fac\195\167\195\163o NPC",
            ["Player faction"] = "Fac\195\167\195\181es do Jogador",
            ["Player Factions"] = "Fac\195\167\195\181es do Jogador",
            ["Your Group"] = "Seu Grupo",
            ["Grupo Your"] = "Seu Grupo",
            ["[YOUR PARTY]"] = "[SEU GRUPO]",
            ["members"] = "Membros",
            ["membros"] = "Membros",
            ["No home yet"] = "Sem base definida",
            ["neutral"] = "Neutro",
            ["neutro"] = "Neutro",
            ["Home Base"] = "Base Principal",
            ["Main Base"] = "Base Principal",
            ["Residents:"] = "Residentes:",
            ["Zones:"] = "Zonas:",
            ["Tasks:"] = "Tarefas:",
            ["queued"] = "em fila",
            ["active"] = "ativas",
            ["working"] = "trabalhando",
            ["idle"] = "ociosos",
            ["resting"] = "descansando",
            ["Resting"] = "Descansando",
            ["Relaxing"] = "Relaxando",
            ["Security:"] = "Seguran\195\167a:",
            ["patrol"] = "patrulha",
            ["Boundary:"] = "Limite:",
            ["all floors"] = "todos os andares",
            ["Work Areas"] = "\195\129reas de Trabalho",
            ["Add Area"] = "Adicionar \195\129rea",
            ["Guard Post"] = "Posto de Guarda",
            ["Patrol Area"] = "\195\129rea de Patrulha",
            ["Farming Area"] = "\195\129rea de Cultivo",
            ["Woodcutting Area"] = "\195\129rea de Corte de Madeira",
            ["Log Processing Area"] = "\195\129rea de Processamento de Toras",
            ["Corpse Drop Area"] = "\195\129rea de Descarte de Cad\195\161veres",
            ["Corpse Drop"] = "Descarte de Cad\195\161veres",
            ["View Card"] = "Ver Cart\195\163o",
            ["Set Job"] = "Definir Trabalho",
            ["Work:"] = "Trabalho:",
            ["Work"] = "Trabalho",
            ["waiting"] = "aguardando",
            ["blocked"] = "bloqueado",
            ["No residents"] = "Nenhum residente",
            ["Assign"] = "Atribuir",
            ["Storage:"] = "Armazenamento:",
            ["assigned"] = "definido(s)",
            ["shortage(s)"] = "em falta",
            ["stock unavailable"] = "estoque indispon\195\173vel",
            ["Food & Drink"] = "Comida e Bebida",
            ["Food"] = "Comida",
            ["Water"] = "\195\129gua",
            ["Medical"] = "Suprimentos M\195\169dicos",
            ["Weapons"] = "Armas",
            ["Ammunition"] = "Muni\195\167\195\163o",
            ["Tools"] = "Ferramentas",
            ["Materials"] = "Materiais",
            ["Clothing"] = "Roupas",
            ["Junk"] = "Lixo / Diversos",

            -- G. Diálogos e Falas do Chat
            ["Right behind you."] = "Logo atr\195\161s de voc\195\170.",
            ["I'll take a breather."] = "Vou dar uma respirada.",
            ["I'll stay here."] = "Vou ficar aqui.",
            ["I'm heading there."] = "Estou indo para l\195\161.",
            ["I'm here."] = "Estou aqui.",
            ["I'll hold that position."] = "Vou manter essa posi\195\167\195\163o.",
            ["I'll patrulha it."] = "Vou patrulh\195\161-la.",
            ["I'll patrol it."] = "Vou patrulh\195\161-la.",
            ["I'll search the area."] = "Vou procurar na \195\129rea.",
            ["I'll check the bodies."] = "Vou checar os corpos.",
            ["I've checked the area."] = "J\195\161 chequei a \195\129rea.",
            ["I'll search the building."] = "Vou vasculhar o edif\195\173cio.",
            ["I'll look for food."] = "Vou procurar por comida.",
            ["I'll look for water."] = "Vou procurar por \195\161gua.",
            ["I'll look for medical supplies."] = "Vou procurar por suprimentos m\195\169dicos.",
            ["I could use medical supplies."] = "Preciso de suprimentos m\195\169dicos.",
            ["I'll look for a weapon."] = "Vou procurar por uma arma."
        }

        local sortedUiKeys = {}
        for k in pairs(uiReplacements) do
            table.insert(sortedUiKeys, k)
        end
        table.sort(sortedUiKeys, function(a, b)
            return #a > #b
        end)

        if not KnoxBaseManager.ptBrPatchedUI then
            if ISComboBox then
                local oldComboAddOption = ISComboBox.addOption
                ISComboBox.addOption = function(self, text, data, selected)
                    if text and type(text) == "string" and uiReplacements[text] then
                        text = uiReplacements[text]
                    end
                    return oldComboAddOption(self, text, data, selected)
                end
            end

            if ISTabPanel then
                local oldAddTab = ISTabPanel.addView
                ISTabPanel.addView = function(self, name, view, ...)
                    if name and type(name) == "string" then
                        if name == "Base" then name = "Base"
                        elseif name == "Residents" then name = "Residentes"
                        elseif name == "Work" then name = "Trabalho"
                        elseif name == "Away" then name = "Ausente"
                        elseif name == "Survivors" then name = "Sobreviventes"
                        elseif name == "Factions" then name = "Fac\195\167\195\181es"
                        end
                    end
                    return oldAddTab(self, name, view, ...)
                end
            end

            local oldDrawText = ISUIElement.drawText
            ISUIElement.drawText = function(self, str, x, y, r, g, b, a, font, ...)
                if str and type(str) == "string" then
                    if uiReplacements[str] then
                        str = uiReplacements[str]
                    else
                        -- Correções de frases mescladas/dinâmicas em 'Residentes' e UI
                        if string.find(str, "Find Comida") or string.find(str, "Find Food") then
                            str = string.gsub(str, "Find Comida", "Procurar comida")
                            str = string.gsub(str, "Find Food", "Procurar comida")
                        elseif string.find(str, "Find %f[%a]\195\129gua") or string.find(str, "Find Water") then
                            str = string.gsub(str, "Find \195\129gua", "Procurar \195\161gua")
                            str = string.gsub(str, "Find Water", "Procurar \195\161gua")
                        elseif string.find(str, "Find Suprimentos") or string.find(str, "Find Medical") then
                            str = "Procurar suprimentos m\195\169dicos"
                        end

                        -- Painel Squad 1
                        if string.find(str, "Waiting here %- %d+ tiles") or string.find(str, "Waiting here %- %d+ tile") then
                            str = string.gsub(str, "Waiting here %- (%d+) tiles", "Esperando aqui - %1 piso(s)")
                            str = string.gsub(str, "Waiting here %- (%d+) tile", "Esperando aqui - %1 piso(s)")
                        end

                        if string.find(str, "rout%.%.%.") or string.find(str, "rout%f[%s%p]") then
                            str = string.gsub(str, "rout%.%.%.", "rota...")
                            str = string.gsub(str, "rout", "rota")
                        end

                        -- Diálogos / Log de Chat
                        if string.find(str, "%[YOUR PARTY%]") then
                            str = string.gsub(str, "%[YOUR PARTY%]", "[SEU GRUPO]")
                        end

                        if string.find(str, "The rota is bloqueado") or string.find(str, "The route is blocked") then
                            str = string.gsub(str, "The rota is bloqueado%. I'll keep watch and try again%.", "A rota est\195\161 bloqueada. Vou ficar de olho e tentar novamente.")
                            str = string.gsub(str, "The route is blocked%. I'll keep watch and try again%.", "A rota est\195\161 bloqueada. Vou ficar de olho e tentar novamente.")
                        end

                        -- Padrões da Base e Instruções
                        if string.find(str, "Assign storage:") or string.find(str, "right%-click a container") then
                            str = "Atribuir armazenamento: clique com o bot\195\163o direito em um cont\195\170iner na base > Usar para..."
                        elseif string.find(str, "Storage is assigned by") or string.find(str, "Storage is defined by") then
                            str = "O armazenamento \195\169 definido ao clicar com o bot\195\163o direito em um cont\195\170iner na base."
                        elseif string.find(str, "No work areas") or string.find(str, "pick a type") then
                            str = "Sem \195\161reas de trabalho: escolha um tipo, clique em Adicionar e arraste."
                        elseif string.find(str, "No work") and string.find(str, "mark work areas") then
                            str = "Sem tarefas na fila: marque \195\161reas de trabalho."
                        elseif string.find(str, "Right%-click a container at home") then
                            str = string.gsub(str, "Right%-click a container at home > Use for", "Bot\195\163o direito no cont\195\170iner > Usar p/")
                        end

                        if string.find(str, "has passed away") then
                            str = string.gsub(str, "has passed away%.", "faleceu.")
                        end

                        if string.find(str, "with group") then str = string.gsub(str, "with group", "com grupo") end
                        if string.find(str, "Regrouping") then str = string.gsub(str, "Regrouping", "Reagrupando") end
                        if string.find(str, "Storing supplies") then str = string.gsub(str, "Storing supplies", "Guardando suprimentos") end
                        if string.find(str, "Looking for supplies") then str = string.gsub(str, "Looking for supplies", "Procurando Suprimentos") end
                        if string.find(str, " after ") then str = string.gsub(str, " after ", " ap\195\180s ") end
                        if string.find(str, " | Away | ") then str = string.gsub(str, " | Away | ", " | Ausente | ") end
                        if string.find(str, "Supply run:") then str = string.gsub(str, "Supply run:", "Busca de Suprimentos:") end

                        if string.find(str, "at %d+, %d+, floor") or string.find(str, "em %d+, %d+, andar") then
                            if string.find(str, "guardaa%-roupa") then
                                str = string.gsub(str, "guardaa%-roupa", "guarda-roupa")
                            end

                            if not string.find(str, "guarda%-roupa") then
                                str = string.gsub(str, "%(wardrobe%)", "(guarda-roupa)")
                            end

                            str = string.gsub(str, "Clothing", "Roupas")
                            str = string.gsub(str, "Food & Drink", "Comida e Bebida")
                            str = string.gsub(str, "Food", "Comida")
                            str = string.gsub(str, "Water", "\195\129gua")
                            str = string.gsub(str, "Medical", "Suprimentos M\195\169dicos")
                            str = string.gsub(str, "Weapons", "Armas")
                            str = string.gsub(str, "Ammunition", "Muni\195\167\195\163o")
                            str = string.gsub(str, "Tools", "Ferramentas")
                            str = string.gsub(str, "Materials", "Materiais")
                            str = string.gsub(str, "Junk", "Lixo / Diversos")

                            str = string.gsub(str, "%(counter%)", "(balc\195\163o)")
                            str = string.gsub(str, "%(shelves%)", "(prateleiras)")
                            str = string.gsub(str, "%(dresser%)", "(c\195\180moda)")
                            str = string.gsub(str, "%(fridge%)", "(geladeira)")
                            
                            str = string.gsub(str, " at ", " em ")
                            str = string.gsub(str, "floor", "andar")
                        end

                        if string.find(str, "Storage:") or string.find(str, "Armazenamento:") then
                            str = string.gsub(str, "Storage:", "Armazenamento:")
                            str = string.gsub(str, "assigned", "definido(s)")
                            str = string.gsub(str, "shortage%(s%)", "em falta")
                        end

                        if string.find(str, "needs") then
                            str = string.gsub(str, "needs", "em falta:")
                            str = string.gsub(str, "Food", "Comida")
                            str = string.gsub(str, "Water", "\195\129gua")
                            str = string.gsub(str, "Medical", "M\195\169dicos")
                            str = string.gsub(str, "Weapons", "Armas")
                            str = string.gsub(str, "Tools", "Ferramentas")
                        end

                        if string.find(str, " Crew") or string.find(str, " Group") or string.find(str, " Gang") or string.find(str, " Squad") or string.find(str, "'s People") or string.find(str, "Base:") or string.find(str, "Grupo Your") then
                            str = string.gsub(str, "Grupo Your", "Seu Grupo")

                            str = string.gsub(str, "Base:%s*The ([%w%s%-]+) Crew Base", "Base: Grupo %1")
                            str = string.gsub(str, "Base:%s*The ([%w%s%-]+) Group Base", "Base: Grupo %1")
                            str = string.gsub(str, "Base:%s*The ([%w%s%-]+) Gang Base", "Base: Gangue %1")
                            str = string.gsub(str, "Base:%s*([%w%s%-]+)'s People Base", "Base: Grupo %1")

                            str = string.gsub(str, "The ([%w%s%-]+) Crew", "Grupo %1")
                            str = string.gsub(str, "The ([%w%s%-]+) Group", "Grupo %1")
                            str = string.gsub(str, "The ([%w%s%-]+) Gang", "Gangue %1")
                            str = string.gsub(str, "The ([%w%s%-]+) Squad", "Esquadr\195\163o %1")
                            str = string.gsub(str, "([%w%s%-]+)'s People", "Grupo %1")
                            str = string.gsub(str, "([%w%s%-]+) Crew", "Grupo %1")
                            str = string.gsub(str, "([%w%s%-]+) Group", "Grupo %1")

                            str = string.gsub(str, "Base:", "Base: ")
                        end

                        for _, orig in ipairs(sortedUiKeys) do
                            local trans = uiReplacements[orig]
                            if string.find(str, orig, 1, true) then
                                str = string.gsub(str, orig, trans)
                            end
                        end
                    end
                end
                return oldDrawText(self, str, x, y, r, g, b, a, font, ...)
            end

            KnoxBaseManager.ptBrPatchedUI = true
        end
    end

    -- 3. MENUS DE CONTEXTO
    if ISContextMenu and ISContextMenu.addOption and not ISContextMenu.ptBrPatched then
        local oldAddOption = ISContextMenu.addOption
        local contextTranslations = {
            ["Allow"] = "Permitir",
            ["Disallow"] = "Proibir",           
            ["Party Orders"] = "Ordens do Grupo",
            ["Open Base Management"] = "Abrir Gerenciamento da Base",
            ["Establish Home Base"] = "Estabelecer Base Principal",
            ["Establish Base Principal"] = "Estabelecer Base Principal",
            ["Move Base Principal Here"] = "Mover Base Principal para Aqui",
            ["Move Home Base Here"] = "Mover Base Principal para Aqui",
            ["Resident Orders"] = "Ordens para Residentes",
			["Lock Door at Base"] = "Trancar Porta da Base",
            ["Scout Here"] = "Patrulhar Aqui",
            ["Barricade Building Windows"] = "Barricar Janelas da Edifica\195\167\195\163o",
            ["Set Storage"] = "Definir Armazenamento",
            ["Set Storage Containers"] = "Definir Cont\195\170ineres de Armazenamento",
            ["Use for Food & Drink"] = "Usar para Comida e Bebida",
            ["Use for Water"] = "Usar para \195\129gua",
            ["Use for Medical"] = "Usar para Suprimentos M\195\169dicos",
            ["Use for Weapons"] = "Usar para Armas",
            ["Use for Ammunition"] = "Usar para Muni\195\167\195\163o",
            ["Use for Tools"] = "Usar para Ferramentas",
            ["Use for Materials"] = "Usar para Materiais",
            ["Use for Farming"] = "Usar para Agricultura",
            ["Use for Clothing"] = "Usar para Roupas",
            ["Use for Junk"] = "Usar para Lixo / Diversos",
            ["Paired - spacing 1"] = "Em Duplas - Espa\195\167amento 1",
            ["Paired - spacing 2"] = "Em Duplas - Espa\195\167amento 2",
            ["Paired - spacing 3"] = "Em Duplas - Espa\195\167amento 3",
            ["Single File - spacing 1"] = "Fila Indiana - Espa\195\167amento 1",
            ["Single File - spacing 2"] = "Fila Indiana - Espa\195\167amento 2",
            ["Single File - spacing 3"] = "Fila Indiana - Espa\195\167amento 3",
            ["Base Work Orders"] = "Trabalhos da Base",
            ["Vehicle Orders"] = "Ordens de Ve\195\173culo",
            ["Orders for This Location"] = "Ordens para este Local",
            ["Show Activity Feed"] = "Exibir Feed de Atividades",
            ["Manage"] = "Gerenciar",
            ["Move to Location"] = "Ir Para o Local",
            ["Guard Location"] = "Guardar Local",
            ["Patrol Area"] = "Patrulhar \195\129rea",
            ["Loot Dead Bodies"] = "Saquear Cad\195\161veres",
            ["Check Party Needs"] = "Verificar Necessidades do Grupo",
            ["Automatic"] = "Autom\195\161tico",
            ["Guard"] = "Vigiar",
            ["Patrol"] = "Patrulhar",
            ["Farming"] = "Cultivar",
            ["Cooking"] = "Cozinhar",
            ["Woodwork"] = "Marcenaria",
            ["Barricade Windows"] = "Barricar Janelas",
            ["Move Corpses"] = "Mover Cad\195\161veres",
            ["Repair"] = "Reparar",
            ["Rest / Recover"] = "Descansar / Recuperar",
            ["Enter Vehicle"] = "Entrar no Ve\195\173culo",
            ["Exit Vehicle"] = "Sair do Ve\195\173culo",
            ["Move Party Here"] = "Mover Grupo para C\195\161",
            ["Guard This Location"] = "Vigiar este Local",
            ["Patrol This Area"] = "Patrulhar esta \195\129rea",
            ["Open Survivor Notebook"] = "Abrir Bloco de Notas do Sobrevivente",
            ["Loot Orders"] = "Ordens de Saque",
            ["Survival Orders"] = "Ordens de Sobreviv\195\170ncia",
            ["Manage Inventory"] = "Gerenciar Invent\195\161rio",
            ["Medical Check"] = "Avalia\195\167\195\163o M\195\169dica",
            ["View Survivor"] = "Ver Sobrevivente",
            ["Talk"] = "Conversar",
            ["Care"] = "Cuidados",
            ["Orders"] = "Ordens",
            ["Dismiss"] = "Dispensar",
            ["Movement"] = "Movimento",
            ["Tactics & Behavior"] = "T\195\161ticas e Comportamento",
            ["Formation"] = "Forma\195\167\195\163o",
            ["Combat Stance"] = "Postura de Combate",
            ["Weapon Preference"] = "Prefer\195\170ncia de Arma",
            ["Prefer Melee"] = "Preferir Corpo a Corpo",
            ["Prefer Ranged"] = "Preferir Ataque \195\160 Dist\195\162ncia",
            ["Survivor Choice"] = "Escolha do Sobrevivente",
            ["Vaulting and Climbing"] = "Saltar e Escalar",
            ["Doors and Windows"] = "Portas e Janelas",
            ["Allow Vaulting and Climbing"] = "Permitir Saltar e Escalar",
            ["Disallow Vaulting and Climbing"] = "Proibir Saltar e Escalar",
            ["Allow Opening Doors and Windows"] = "Permitir Abrir Portas e Janelas",
            ["Disallow Opening Doors and Windows"] = "Proibir Abrir Portas e Janelas",
            ["Unstick Survivor"] = "Desencalhar Sobrevivente",
            ["Loot Runs"] = "Corridas de Saque",
            ["Allow Loot Runs"] = "Permitir Corridas de Saque",
            ["Stay Home"] = "Ficar em Casa",
            ["Talk to Survivor"] = "Conversar com Sobrevivente",
            ["Ask About Needs"] = "Perguntar sobre Necessidades",
            ["Tell Joke"] = "Contar Piada",
            ["Compliment"] = "Elogiar",
            ["Make Funny Face"] = "Fazer Cara Engra\195\167ada",
            ["Offer Gift"] = "Oferecer Presente",
            ["Give Money"] = "Dar Dinheiro",
            ["Insult"] = "Insultar",
            ["Slap"] = "Dar um Tapa"
        }

        ISContextMenu.addOption = function(self, text, target, onMouseDown, ...)
            local translatedText = text
            if text then
                if string.find(text, "Stop ") then
                    translatedText = string.gsub(text, "Stop ", "Interromper ")
                    translatedText = string.gsub(translatedText, "Relaxando", "Relaxar")
                    translatedText = string.gsub(translatedText, "Descansando", "Descansar")
                    translatedText = string.gsub(translatedText, "Patrulhando", "Patrulhar")
                    translatedText = string.gsub(translatedText, "Trabalhando", "Trabalhar")
                    translatedText = string.gsub(translatedText, "Cultivando", "Cultivar")
                elseif string.find(text, "Assigned:") then
                    translatedText = string.gsub(text, "Assigned:", "Atribu\195\173do:")
                    translatedText = string.gsub(translatedText, "Food & Drink", "Comida e Bebida")
                    translatedText = string.gsub(translatedText, "Water", "\195\129gua")
                    translatedText = string.gsub(translatedText, "Medical", "Suprimentos M\195\169dicos")
                    translatedText = string.gsub(translatedText, "Weapons", "Armas")
                    translatedText = string.gsub(translatedText, "Ammunition", "Muni\195\167\195\163o")
                    translatedText = string.gsub(translatedText, "Tools", "Ferramentas")
                    translatedText = string.gsub(translatedText, "Materials", "Materiais")
                    translatedText = string.gsub(translatedText, "Farming", "Agricultura")
                    translatedText = string.gsub(translatedText, "Clothing", "Roupas")
                    translatedText = string.gsub(translatedText, "Junk", "Lixo / Diversos")
                elseif string.find(text, "Stop Using for") then
                    translatedText = string.gsub(text, "Stop Using for", "Interromper Usar para")
                    translatedText = string.gsub(translatedText, "Junk", "Lixo / Diversos")
                    translatedText = string.gsub(translatedText, "Cultivar", "Agricultura")
                    translatedText = string.gsub(translatedText, "Farming", "Agricultura")
                    translatedText = string.gsub(translatedText, "Materials", "Materiais")
                    translatedText = string.gsub(translatedText, "Food & Drink", "Comida e Bebida")
                    translatedText = string.gsub(translatedText, "Water", "\195\129gua")
                    translatedText = string.gsub(translatedText, "Clothing", "Roupas")
                    translatedText = string.gsub(translatedText, "Ammunition", "Muni\195\167\195\163o")
                    translatedText = string.gsub(translatedText, "Weapons", "Armas")
                    translatedText = string.gsub(translatedText, "Medical", "Suprimentos M\195\169dicos")
                    translatedText = string.gsub(translatedText, "Tools", "Ferramentas")
                elseif string.find(text, "Move Base") or string.find(text, "Move Home") then
                    translatedText = string.gsub(text, "Move Base Principal Here", "Mover Base Principal para Aqui")
                    translatedText = string.gsub(translatedText, "Move Home Base Here", "Mover Base Principal para Aqui")
                elseif string.find(text, "fridge") then
                    translatedText = string.gsub(text, "fridge", "Geladeira")
                elseif string.find(text, "freezer") then
                    translatedText = string.gsub(text, "freezer", "Freezer")
                elseif string.find(text, "Passive") and string.find(text, "stay close") then
                    translatedText = "Passivo - Ficar Perto"
                elseif string.find(text, "Defensive") and string.find(text, "protect us") then
                    translatedText = "Defensivo - Proteger-nos"
                elseif string.find(text, "Aggressive") and string.find(text, "clear threats") then
                    translatedText = "Agressivo - Eliminar Amea\195\167as"
                else
                    for orig, trans in pairs(contextTranslations) do
                        if text == orig then
                            translatedText = trans
                            break
                        end
                    end
                end
            end
            return oldAddOption(self, translatedText, target, onMouseDown, ...)
        end

        ISContextMenu.ptBrPatched = true
    end
end

Events.OnGameStart.Add(InjetorTraducaoKnox)