module sc (
    input  logic       clk,         // Clock do sistema (100 MHz na DE2-115)
    input  logic       rst,         // Reset assíncrono ativo-alto
    input  logic [3:0] btn,         // Entradas dos botões (BTN[3:0])
    output logic       unlocked,    // Saída: 1 quando o cofre está desbloqueado
    output logic       lock_led     // LED vermelho indica bloqueio ativo
);

    // one-hot encoding para 7 estados
    typedef enum logic [6:0] {
        S0       = 7'b0000001,  // Estado inicial
        S1       = 7'b0000010,  // Código 1 OK
        S2       = 7'b0000100,  // Código 2 OK
        S3       = 7'b0001000,  // Desbloqueado
        PROG_S0  = 7'b0010000,  // Programando senha parte 1
        PROG_S1  = 7'b0100000,  // Programando senha parte 2
        PROG_S2  = 7'b1000000   // Programando senha parte 3
    } state_t;

    state_t state, next;

    // Senha programável
    logic [3:0] passcode[2:0];

    // Contadores e flags
    logic [1:0]  error_count;       // Conta erros (0 a 3)
    logic        locked;            // Flag de bloqueio ativo
    logic [31:0] timeout_counter;   // Contador para 10 segundos

    localparam int TIMEOUT_MAX = 1_000_000_000; // 100 MHz * 10 s

    // BLOCO PRINCIPAL SEQUENCIAL
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // Reset geral
            state <= S0;
            passcode[0] <= 4'b0111;
            passcode[1] <= 4'b1101;
            passcode[2] <= 4'b1101;
            error_count <= 0;
            locked <= 0;
            timeout_counter <= 0;
        end
        else begin
            if (locked) begin
                // Se bloqueado, ignora FSM e só conta tempo
                if (timeout_counter < TIMEOUT_MAX) begin
                    timeout_counter <= timeout_counter + 1;
                end
                else begin
                    locked <= 0;                  // Libera após 10s
                    timeout_counter <= 0;
                    error_count <= 0;             // Zera erros
                    state <= S0;                  // Volta ao início
                end
            end
            else begin
                // Atualiza FSM normalmente
                state <= next;

                // Programação de senha
                case (state)
                    PROG_S0: if (|btn) passcode[0] <= btn;
                    PROG_S1: if (|btn) passcode[1] <= btn;
                    PROG_S2: if (|btn) passcode[2] <= btn;
                    default: ;
                endcase

                // ===== Contagem de erros =====
                if ((state == S0 && |btn && btn != passcode[0]) ||
                    (state == S1 && |btn && btn != passcode[1]) ||
                    (state == S2 && |btn && btn != passcode[2])) begin
                    if (error_count < 2)
                        error_count <= error_count + 1;
                    else begin
                        locked <= 1;            // Bloqueia após 3 erros
                        timeout_counter <= 0;   // Inicia temporizador
                    end
                end
                else if ((state == S1 && btn == passcode[1]) ||
                         (state == S2 && btn == passcode[2]) ||
                         (state == S3)) begin
                    error_count <= 0;           // Acertou, zera erros
                end
            end
        end
    end

    // Lógica Combinacional FSM
    always_comb begin
        next = state;
        if (!locked) begin
            case (state)
                S0: begin
                    if (btn == passcode[0]) next = S1;
                    else if (|btn) next = S0;
                end

                S1: begin
                    if (btn == passcode[1]) next = S2;
                    else if (|btn) next = S0;
                end

                S2: begin
                    if (btn == passcode[2]) next = S3;
                    else if (|btn) next = S0;
                end

                S3: begin
                    if (btn == 4'b0001) next = PROG_S0;
                    else next = S3;
                end

                PROG_S0: if (|btn) next = PROG_S1;
                PROG_S1: if (|btn) next = PROG_S2;
                PROG_S2: if (|btn) next = S0;

                default: next = S0;
            endcase
        end
    end

    // Saídas
    always_comb begin
        unlocked = (state == S3);
        lock_led = locked;  // LED vermelho acende no bloqueio
    end

endmodule
