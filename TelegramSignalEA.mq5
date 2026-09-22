//+------------------------------------------------------------------+
//|                                         TelegramSignalEA.mq5     |
//|         EA que monitora sinal do Telegram e executa ordens       |
//|                                                                  |
//|  INSTRUCOES DE USO:                                              |
//|  1. Compile e copie para: <MT5>\MQL5\Experts\                    |
//|  2. Configure o Python para gravar em uma das opcoes abaixo:     |
//|     - InpUsarCommon = true  =>  %AppData%\MetaQuotes\            |
//|                                 Terminal\Common\Files\           |
//|     - InpUsarCommon = false =>  <MT5_Data>\MQL5\Files\           |
//|  3. Anexe o EA a qualquer grafico (de preferencia do ativo)      |
//|  4. Habilite "Permitir negociacao automatica"                    |
//|                                                      
//| C:\Users\Joas Souza\AppData\Roaming\MetaQuotes\Terminal\Common\Files  |
//|  FORMATO DO ARQUIVO ESPERADO (sinal_mt5.txt):                    |
//|    PAR=XAUUSD                                                    |
//|    TIPO=SELL                                                      |
//|    PRECO=4362                                                     |
//|    SL=4375                                                        |
//|    TP1=4359                                                       |
//|    TP2=4356  (opcional)                                           |
//|    ...                                                            |
//+------------------------------------------------------------------+
#property copyright "TelegramSignalEA"
#property link      ""
#property version   "1.20"
#property description "Le sinal de arquivo gerado pelo escutador Telegram e executa ordens"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--- ================================================================
//--- PARAMETROS DE ENTRADA
//--- ================================================================

input group "=== Arquivo de Sinal ==="
input string   InpNomeArquivo   = "sinal_mt5.txt";  // Nome do arquivo de sinal
input bool     InpUsarCommon    = true;              // true = pasta Common MT5 | false = pasta MQL5\Files

input group "=== Parametros de Ordem ==="
input double   InpLotagem       = 0.01;             // Volume em lotes
input int      InpTPUsar        = 1;                // Qual TP usar (1=TP1, 2=TP2, ...)
input ulong    InpMagicNumber   = 777777;           // Magic Number do EA
input int      InpSlippage      = 30;               // Slippage maximo (pontos)

input group "=== Trailing Stop ==="
input bool     InpTrailingAtivo = true;             // Ativar trailing stop
input int      InpTrailingMin   = 5;                // Distancia minima para acionar trailing (pontos)

//--- ================================================================
//--- VARIAVEIS GLOBAIS
//--- ================================================================

CTrade        g_trade;
CPositionInfo g_pos;
COrderInfo    g_ord;

string        g_hashAnterior  = "";   // Hash do ultimo sinal lido
string        g_gvTrailName   = "";   // Nome da GlobalVariable de trailing

//--- Estrutura de sinal
struct Sinal
{
    string symbol;
    string tipo;     // "BUY" ou "SELL"
    double preco;    // Preco de entrada (0 = mercado)
    double sl;       // Stop Loss
    double tp;       // Take Profit (TP selecionado)
    bool   valido;
};

//+------------------------------------------------------------------+
//| Inicializacao                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
    g_gvTrailName = "TelEA_Trail_" + IntegerToString(InpMagicNumber);

    g_trade.SetExpertMagicNumber(InpMagicNumber);
    g_trade.SetDeviationInPoints(InpSlippage);
    g_trade.SetTypeFilling(ORDER_FILLING_RETURN);

    // Ler arquivo na inicializacao apenas para popular hash
    // (evita re-executar sinal antigo ao reiniciar o EA)
    g_hashAnterior = LerConteudoArquivo();

    // Timer de 1 segundo
    EventSetTimer(1);

    Print("=================================================");
    Print(" TelegramSignalEA v1.20 - Iniciado");
    Print(" Arquivo  : ", InpNomeArquivo);
    Print(" Common   : ", InpUsarCommon ? "SIM" : "NAO");
    Print(" Lote     : ", InpLotagem);
    Print(" TP usar  : TP", InpTPUsar);
    Print(" Magic    : ", InpMagicNumber);
    Print(" Trailing : ", InpTrailingAtivo ? "ATIVO" : "INATIVO");
    Print("=================================================");

    // Se ja ha posicao aberta e trailing salvo, informar
    if(TemPosicaoAberta() && GlobalVariableCheck(g_gvTrailName))
    {
        double trail = GlobalVariableGet(g_gvTrailName);
        Print("Posicao aberta encontrada. Trailing recuperado: ", trail, " pts");
    }

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Desinicializacao                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    EventKillTimer();
}

//+------------------------------------------------------------------+
//| OnTick - aplica trailing a cada tick para precisao              |
//+------------------------------------------------------------------+
void OnTick()
{
    if(InpTrailingAtivo)
        AplicarTrailingStop();
}

//+------------------------------------------------------------------+
//| OnTimer - verificar arquivo a cada 1 segundo                    |
//+------------------------------------------------------------------+
void OnTimer()
{
    LerArquivoESinalar();

    if(InpTrailingAtivo)
        AplicarTrailingStop();
}

//+------------------------------------------------------------------+
//| Le o conteudo do arquivo de sinal                               |
//+------------------------------------------------------------------+
string LerConteudoArquivo()
{
    int flags = FILE_READ | FILE_TXT | FILE_ANSI;
    if(InpUsarCommon) flags |= FILE_COMMON;

    int handle = FileOpen(InpNomeArquivo, flags);
    if(handle == INVALID_HANDLE)
        return "";

    string conteudo = "";
    while(!FileIsEnding(handle))
    {
        string linha = FileReadString(handle);
        StringTrimRight(linha);
        StringTrimLeft(linha);
        if(linha != "")
            conteudo += linha + "\n";
    }
    FileClose(handle);

    return conteudo;
}

//+------------------------------------------------------------------+
//| Verifica se arquivo mudou e processa novo sinal                 |
//+------------------------------------------------------------------+
void LerArquivoESinalar()
{
    string conteudo = LerConteudoArquivo();

    if(conteudo == "" || conteudo == g_hashAnterior)
        return;  // Sem mudanca ou arquivo vazio

    // Novo sinal detectado!
    g_hashAnterior = conteudo;

    Print("--- NOVO SINAL RECEBIDO ---");
    Print(conteudo);
    Print("---------------------------");

    ProcessarSinal(conteudo);
}

//+------------------------------------------------------------------+
//| Faz o parse do conteudo e retorna struct Sinal                  |
//+------------------------------------------------------------------+
Sinal ParseSinal(const string conteudo)
{
    Sinal s;
    s.symbol = "";
    s.tipo   = "";
    s.preco  = 0.0;
    s.sl     = 0.0;
    s.tp     = 0.0;
    s.valido = false;

    string tpKey = "TP" + IntegerToString(InpTPUsar) + "=";

    string linhas[];
    int nLinhas = StringSplit(conteudo, '\n', linhas);

    bool tpEncontrado = false;

    for(int i = 0; i < nLinhas; i++)
    {
        string ln = linhas[i];
        StringTrimLeft(ln);
        StringTrimRight(ln);

        if(StringFind(ln, "PAR=")   == 0)  s.symbol = StringSubstr(ln, 4);
        if(StringFind(ln, "TIPO=")  == 0)  s.tipo   = StringSubstr(ln, 5);
        if(StringFind(ln, "PRECO=") == 0)  s.preco  = StringToDouble(StringSubstr(ln, 6));
        if(StringFind(ln, "SL=")    == 0)  s.sl     = StringToDouble(StringSubstr(ln, 3));
        if(StringFind(ln, tpKey)    == 0)
        {
            s.tp = StringToDouble(StringSubstr(ln, StringLen(tpKey)));
            tpEncontrado = true;
        }
    }

    // Fallback: se TP escolhido nao existe, usar TP1
    if(!tpEncontrado)
    {
        for(int i = 0; i < nLinhas; i++)
        {
            string ln = linhas[i];
            StringTrimRight(ln);
            if(StringFind(ln, "TP1=") == 0)
            {
                s.tp = StringToDouble(StringSubstr(ln, 4));
                if(InpTPUsar != 1)
                    Print("TP", InpTPUsar, " nao encontrado no sinal. Usando TP1 como fallback.");
                break;
            }
        }
    }

    // Limpar espacos em branco extras
    StringTrimLeft(s.symbol);
    StringTrimRight(s.symbol);
    StringTrimLeft(s.tipo);
    StringTrimRight(s.tipo);

    // Validacao minima
    if(s.symbol != "" && (s.tipo == "BUY" || s.tipo == "SELL") && s.sl > 0.0)
        s.valido = true;

    return s;
}

//+------------------------------------------------------------------+
//| Processa o sinal e decide se abre ordem                         |
//+------------------------------------------------------------------+
void ProcessarSinal(const string conteudo)
{
    if(TemPosicaoAberta())
    {
        Print("Posicao ja aberta pelo EA. Sinal ignorado.");
        return;
    }

    if(TemOrdemPendente())
    {
        Print("Ordem pendente aberta pelo EA. Sinal ignorado.");
        return;
    }

    Sinal s = ParseSinal(conteudo);

    if(!s.valido)
    {
        Print("ERRO: Sinal invalido ou incompleto. Campos obrigatorios: PAR, TIPO, SL.");
        return;
    }

    Print(StringFormat("Sinal OK => PAR=%-8s TIPO=%-4s PRECO=%-10.5f SL=%-10.5f TP=%.5f",
                       s.symbol, s.tipo, s.preco, s.sl, s.tp));

    ExecutarOrdem(s);
}

//+------------------------------------------------------------------+
//| Executa a ordem baseada no sinal                                |
//+------------------------------------------------------------------+
void ExecutarOrdem(Sinal &s)
{
    // Garantir simbolo disponivel
    if(!SymbolSelect(s.symbol, true))
    {
        Print("ERRO: Simbolo '", s.symbol, "' nao encontrado. Verifique o nome exato.");
        return;
    }

    // Aguardar cotacoes validas
    double ask    = SymbolInfoDouble(s.symbol, SYMBOL_ASK);
    double bid    = SymbolInfoDouble(s.symbol, SYMBOL_BID);
    int    digits = (int)SymbolInfoInteger(s.symbol, SYMBOL_DIGITS);
    double point  = SymbolInfoDouble(s.symbol, SYMBOL_POINT);
    double spread = ask - bid;

    if(ask <= 0 || bid <= 0)
    {
        Print("ERRO: Cotacao invalida para ", s.symbol, ". EA sem preco de mercado.");
        return;
    }

    // Normalizar precos do sinal
    s.preco = NormalizeDouble(s.preco, digits);
    s.sl    = NormalizeDouble(s.sl,    digits);
    s.tp    = NormalizeDouble(s.tp,    digits);

    // ----------------------------------------------------------------
    // Calcular distancia do Trailing Stop em pontos
    //   = distancia entre preco de entrada e SL do sinal
    // ----------------------------------------------------------------
    double precoRef   = 0.0;
    double trailPts   = 0.0;

    if(s.tipo == "BUY")
    {
        precoRef = (s.preco > 0.0) ? s.preco : ask;
        trailPts = (precoRef - s.sl) / point;
    }
    else // SELL
    {
        precoRef = (s.preco > 0.0) ? s.preco : bid;
        trailPts = (s.sl - precoRef) / point;
    }

    if(trailPts <= 0)
    {
        Print("ERRO: Distancia de SL invalida (", DoubleToString(trailPts, 1), " pts). ",
              "Verifique PRECO e SL no sinal.");
        return;
    }

    // Salvar trailing em GlobalVariable (persiste entre reinicializacoes)
    GlobalVariableSet(g_gvTrailName, trailPts);
    Print(StringFormat("Trailing Stop = %.1f pts (%.5f)", trailPts, trailPts * point));

    // ----------------------------------------------------------------
    // Ajustar tipo de filling conforme suporte do simbolo
    // ----------------------------------------------------------------
    int fillMode = (int)SymbolInfoInteger(s.symbol, SYMBOL_FILLING_MODE);
    if((fillMode & SYMBOL_FILLING_IOC) != 0)
        g_trade.SetTypeFilling(ORDER_FILLING_IOC);
    else if((fillMode & SYMBOL_FILLING_FOK) != 0)
        g_trade.SetTypeFilling(ORDER_FILLING_FOK);
    else
        g_trade.SetTypeFilling(ORDER_FILLING_RETURN);

    // ----------------------------------------------------------------
    // Determinar tipo de ordem e enviar
    // ----------------------------------------------------------------
    string comentario = StringFormat("TelSig_TP%d", InpTPUsar);
    bool   resultado  = false;

    // Tolerancia para considerar "a mercado": 3x o spread
    double tolerancia = MathMax(spread * 3.0, point * 3.0);

    if(s.tipo == "BUY")
    {
        if(s.preco <= 0.0 || MathAbs(s.preco - ask) <= tolerancia)
        {
            // --- BUY a mercado ---
            Print(StringFormat("Enviando BUY MARKET | Ask=%.5f SL=%.5f TP=%.5f Lote=%.2f",
                               ask, s.sl, s.tp, InpLotagem));
            resultado = g_trade.Buy(InpLotagem, s.symbol, 0, s.sl, s.tp, comentario);
        }
        else if(s.preco > ask)
        {
            // --- BUY STOP (preco acima do mercado atual) ---
            Print(StringFormat("Enviando BUY STOP @ %.5f | Ask=%.5f SL=%.5f TP=%.5f",
                               s.preco, ask, s.sl, s.tp));
            resultado = g_trade.BuyStop(InpLotagem, s.preco, s.symbol,
                                        s.sl, s.tp, ORDER_TIME_GTC, 0, comentario);
        }
        else
        {
            // --- BUY LIMIT (preco abaixo do mercado atual) ---
            Print(StringFormat("Enviando BUY LIMIT @ %.5f | Ask=%.5f SL=%.5f TP=%.5f",
                               s.preco, ask, s.sl, s.tp));
            resultado = g_trade.BuyLimit(InpLotagem, s.preco, s.symbol,
                                         s.sl, s.tp, ORDER_TIME_GTC, 0, comentario);
        }
    }
    else // SELL
    {
        if(s.preco <= 0.0 || MathAbs(s.preco - bid) <= tolerancia)
        {
            // --- SELL a mercado ---
            Print(StringFormat("Enviando SELL MARKET | Bid=%.5f SL=%.5f TP=%.5f Lote=%.2f",
                               bid, s.sl, s.tp, InpLotagem));
            resultado = g_trade.Sell(InpLotagem, s.symbol, 0, s.sl, s.tp, comentario);
        }
        else if(s.preco < bid)
        {
            // --- SELL STOP (preco abaixo do mercado atual) ---
            Print(StringFormat("Enviando SELL STOP @ %.5f | Bid=%.5f SL=%.5f TP=%.5f",
                               s.preco, bid, s.sl, s.tp));
            resultado = g_trade.SellStop(InpLotagem, s.preco, s.symbol,
                                         s.sl, s.tp, ORDER_TIME_GTC, 0, comentario);
        }
        else
        {
            // --- SELL LIMIT (preco acima do mercado atual) ---
            Print(StringFormat("Enviando SELL LIMIT @ %.5f | Bid=%.5f SL=%.5f TP=%.5f",
                               s.preco, bid, s.sl, s.tp));
            resultado = g_trade.SellLimit(InpLotagem, s.preco, s.symbol,
                                          s.sl, s.tp, ORDER_TIME_GTC, 0, comentario);
        }
    }

    // ----------------------------------------------------------------
    // Resultado
    // ----------------------------------------------------------------
    if(resultado)
    {
        Print("ORDEM ENVIADA COM SUCESSO!");
        Print("  Ticket    : ", g_trade.ResultOrder());
        Print("  Preco exec: ", g_trade.ResultPrice());
        Print("  Volume    : ", g_trade.ResultVolume());
    }
    else
    {
        Print("ERRO AO ENVIAR ORDEM!");
        Print("  Codigo    : ", g_trade.ResultRetcode());
        Print("  Descricao : ", g_trade.ResultComment());
        Print("  Dica: Verifique stops minimos e modo de filling do simbolo.");
    }
}

//+------------------------------------------------------------------+
//| Verifica se ha posicoes abertas pelo EA                         |
//+------------------------------------------------------------------+
bool TemPosicaoAberta()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(g_pos.SelectByIndex(i) && g_pos.Magic() == InpMagicNumber)
            return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Verifica se ha ordens pendentes pelo EA                         |
//+------------------------------------------------------------------+
bool TemOrdemPendente()
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(g_ord.SelectByIndex(i) && g_ord.Magic() == InpMagicNumber)
            return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Aplica Trailing Stop nas posicoes abertas                       |
//|                                                                  |
//| Logica: O SL segue o preco mantendo sempre a mesma distancia    |
//|         definida no momento da entrada (= distancia do SL orig) |
//|                                                                  |
//|  BUY : novoSL = BID - trailDist  (so move para cima)           |
//|  SELL: novoSL = ASK + trailDist  (so move para baixo)          |
//+------------------------------------------------------------------+
void AplicarTrailingStop()
{
    // Recuperar distancia de trailing
    double trailPts = 0.0;
    if(GlobalVariableCheck(g_gvTrailName))
        trailPts = GlobalVariableGet(g_gvTrailName);

    if(trailPts <= 0) return;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!g_pos.SelectByIndex(i))    continue;
        if(g_pos.Magic() != InpMagicNumber) continue;

        string sym     = g_pos.Symbol();
        int    digits  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
        double point   = SymbolInfoDouble(sym, SYMBOL_POINT);
        double ask     = SymbolInfoDouble(sym, SYMBOL_ASK);
        double bid     = SymbolInfoDouble(sym, SYMBOL_BID);
        double slAtual = g_pos.StopLoss();
        double tp      = g_pos.TakeProfit();
        ulong  ticket  = g_pos.Ticket();
        double trail   = NormalizeDouble(trailPts * point, digits);

        // Verificar stops minimos do simbolo
        int stopsLevel = (int)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
        double minDist = stopsLevel * point;

        if(g_pos.PositionType() == POSITION_TYPE_BUY)
        {
            double novoSL = NormalizeDouble(bid - trail, digits);

            // Garantir distancia minima do mercado
            if(novoSL > bid - minDist)
                novoSL = NormalizeDouble(bid - minDist, digits);

            // So move SL para cima (nunca para baixo)
            if(novoSL > slAtual + point * InpTrailingMin)
            {
                if(g_trade.PositionModify(ticket, novoSL, tp))
                    Print(StringFormat("TRAIL BUY  | Ticket=%I64u | SL %.5f -> %.5f | Bid=%.5f",
                                       ticket, slAtual, novoSL, bid));
            }
        }
        else if(g_pos.PositionType() == POSITION_TYPE_SELL)
        {
            double novoSL = NormalizeDouble(ask + trail, digits);

            // Garantir distancia minima do mercado
            if(novoSL < ask + minDist)
                novoSL = NormalizeDouble(ask + minDist, digits);

            // So move SL para baixo (ou se slAtual == 0)
            if(slAtual == 0.0 || novoSL < slAtual - point * InpTrailingMin)
            {
                if(g_trade.PositionModify(ticket, novoSL, tp))
                    Print(StringFormat("TRAIL SELL | Ticket=%I64u | SL %.5f -> %.5f | Ask=%.5f",
                                       ticket, slAtual, novoSL, ask));
            }
        }
    }
}
//+------------------------------------------------------------------+
