#include <SDL2/SDL.h>
#include <SDL2/SDL_image.h>
#include "imgui.h"
#include "imgui_impl_sdl2.h"
#include "imgui_impl_sdlrenderer2.h"
#include <cerrno>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <string>
#include <array>
#include <cstdio>
#include <unordered_map>
#include <sys/wait.h>
#include <fcntl.h>

const float buttonHeight = 48.0f;

struct Language {
    std::string name;
    std::string code;
    std::string continue_text;
    std::string back_text;
};

struct HeadphoneWarning {
    std::string title;
    std::string line_1;
    std::string line_2;
    std::string line_3;
    std::string i_accept;
};

const std::array<Language, 10> languages = {{
    {u8"汉语", u8"zh", u8"继续", u8"返回"},
    {u8"Español", u8"es", u8"Continuar", u8"Atrás"},
    {u8"English", u8"en", u8"Continue", u8"Back"},
    {u8"Français", u8"fr", u8"Continuer", u8"Retour"},
    {u8"Português", u8"pt", u8"Continuar", u8"Voltar"},
    {u8"Русский", u8"ru", u8"Продолжить", u8"Назад"},
    {u8"Bahasa Indonesia", u8"id", u8"Lanjutkan", u8"Kembali"},
    {u8"Deutsch", u8"de", u8"Weiter", u8"Zurück"},
    {u8"日本語", u8"ja", u8"次へ", u8"戻る"},
    {u8"Kiswahili", u8"sw", u8"Endelea", u8"Rudi"}
}};

const std::array<HeadphoneWarning, 10> headphone_warning_text = {{
    // 0: zh (汉语)
    {
        u8"警告: 耳机风险",
        u8"耳机音频功能目前为实验性质，正在测试中。可能会发生意外的音量飙升，从而导致听力受损。",
        u8"在设备上使用耳机音频即表示您明确承担使用带来的所有风险。",
        u8"我们目前强烈建议不要在您的设备上使用耳机或耳塞。如果您选择测试耳机音频，请使用外接扬声器进行测试，或在不将耳机直接佩戴在耳上/耳内的情况下进行。",
        u8"我接受"
    },
    // 1: es (Español)
    {
        u8"ADVERTENCIA: RIESGO DE AURICULARES",
        u8"El audio de los auriculares es actualmente experimental y está en fase de pruebas. Pueden producirse picos inesperados de alto volumen que podrían causar daños auditivos.",
        u8"AL UTILIZAR AUDIO DE AURICULARES EN ESTE DISPOSITIVO, ASUME EXPLÍCITAMENTE TODOS LOS RIESGOS DE USO.",
        u8"Recomendamos encarecidamente no utilizar auriculares de casco o de botón en su dispositivo por ahora. Si elige probar el audio de los auriculares, hágalo utilizando altavoces externos o sin llevar los auriculares puestos directamente en los oídos.",
        u8"Acepto"
    },
    // 2: en (English)
    {
        u8"WARNING: HEADPHONE RISK",
        u8"Headphone audio is currently experimental and undergoing testing. Unexpected high-volume spikes may occur which could cause hearing damage.",
        u8"BY USING HEADPHONE AUDIO ON THIS DEVICE, YOU EXPLICITLY ASSUME ALL RISKS OF USE.",
        u8"We strongly advise against using headphones or earbuds on your device for now. If you choose to test headphone audio, test using external speakers or without wearing headphones directly on/in your ears.",
        u8"I Accept"
    },
    // 3: fr (Français)
    {
        u8"AVERTISSEMENT: RISQUE LIÉ AUX ÉCOUTEURS",
        u8"L'audio du casque est actuellement expérimental et en cours de test. Des pics de volume inattendus peuvent se produire et entraîner des lésions auditives.",
        u8"EN UTILISANT L'AUDIO DES ÉCOUTEURS SUR CET APPAREIL, VOUS ASSUMEZ EXPLICITEMENT TOUS LES RISQUES LIÉS À LEUR UTILISATION.",
        u8"Nous vous déconseillons fortement d'utiliser des casques ou des écouteurs sur votre appareil pour le moment. Si vous choisissez de tester l'audio des écouteurs, veuillez le faire à l'aide de haut-parleurs externes ou sans porter les écouteurs directement sur ou dans vos oreilles.",
        u8"J'accepte"
    },
    // 4: pt (Português)
    {
        u8"AVISO: RISCO COM FONES DE OUVIDO",
        u8"O áudio de fones de ouvido é atualmente experimental e está em fase de testes. Podem ocorrer picos repentinos de volume alto que podem causar danos à audição.",
        u8"AO USAR ÁUDIO DE FONES DE OUVIDO NESTE DISPOSITIVO, VOCÊ ASSUME EXPLICITAMENTE TODOS OS RISCOS DE USO.",
        u8"Recomendamos fortemente que não use fones de ouvido ou auriculares no seu dispositivo por enquanto. Se optar por testar o áudio dos fones, faça-o usando alto-falantes externos ou sem colocar os fones diretamente nos ouvidos.",
        u8"Aceito"
    },
    // 5: ru (Русский)
    {
        u8"РИСК ПРИ ИСПОЛЬЗОВАНИИ НАУШНИКОВ",
        u8"Аудио через наушники в настоящее время является экспериментальным и находится на стадии тестирования. Возможны неожиданные скачки громкости, которые могут привести к повреждению слуха.",
        u8"ИСПОЛЬЗУЯ АУДИО В НАУШНИКАХ НА ЭТОМ УСТРОЙСТВЕ, ВЫ ЯВНО БЕРЕТЕ НА СЕБЯ ВСЕ РИСКИ, СВЯЗАННЫЕ С ИХ ИСПОЛЬЗОВАНИЕМ.",
        u8"Рекомендуем не использовать наушники. Тестируйте звук через внешние динамики, не надевая наушники на уши.",
        u8"Я принимаю"
    },
    // 6: id (Bahasa Indonesia)
    {
        u8"PERINGATAN: RISIKO HEADPHONE",
        u8"Audio headphone saat ini bersifat eksperimental dan sedang dalam pengujian. Lonjakan volume tinggi yang tak terduga dapat terjadi yang dapat menyebabkan kerusakan pendengaran.",
        u8"DENGAN MENGGUNAKAN AUDIO HEADPHONE PADA PERANGKAT INI, ANDA SECARA EKSPLISIT MENANGGUNG SEMUA RISIKO PENGGUNAAN.",
        u8"Kami sangat menyarankan agar tidak menggunakan headphone atau earbud di perangkat Anda untuk saat ini. Jika Anda memilih untuk menguji audio headphone, lakukan pengujian menggunakan speaker eksternal atau tanpa mengenakan headphone langsung di/pada telinga Anda.",
        u8"Saya Setuju"
    },
    // 7: Deutsch (de)
    {
        u8"WARNUNG: KOPFHÖRERRISIKO",
        u8"Die Kopfhöreraudioausgabe ist derzeit experimentell und befindet sich in der Testphase. Es kann zu unerwarteten Lautstärkespitzen kommen, die zu Hörschäden führen können.",
        u8"DURCH DIE NUTZUNG VON KOPFHÖRER-AUDIO AUF DIESEM GERÄT ÜBERNEHMEN SIE AUSDRÜCKLICH ALLE RISIKEN DER VERWENDUNG.",
        u8"Wir raten dringend davon ab, derzeit Kopfhörer oder Ohrhörer auf Ihrem Gerät zu verwenden. Wenn Sie Kopfhörer-Audio testen möchten, verwenden Sie externe Lautsprecher oder tragen Sie die Kopfhörer nicht direkt auf oder in Ihren Ohren.",
        u8"Ich akzeptiere"
    },
    // 8: ja (日本語)
    {
        u8"警告: ヘッドホンのリスク",
        u8"ヘッドホンオーディオは現在実験段階であり、テスト中です。予期せぬ大音量の急上昇が発生し、聴覚障害を引き起こす可能性があります。",
        u8"このデバイスでヘッドホンオーディオを使用することにより、お客様は使用に伴うすべてのリスクを明示的に引き受けるものとします。",
        u8"当面の間、デバイスでのヘッドホンやイヤホンの使用は強く非推奨とします。ヘッドホンオーディオをテストする場合は、外部スピーカーを使用するか、ヘッドホンを耳に直接装着せずにテストしてください。",
        u8"同意する"
    },
    // 9: sw (Kiswahili)
    {
        u8"ONYO: HATARI YA VIPOKEA SAUTI VYA MASIKIONI",
        u8"Sauti ya vipokea sauti vya masikioni kwa sasa ni ya majaribio na inapitia upimaji. Ongezeko la ghafla la sauti kubwa linaweza kutokea ambalo linaweza kusababisha uharibifu wa kusikia.",
        u8"KWA KUTUMIA SAUTI YA VIPOKEA SAUTI VYA MASIKIONI KWENYE KIFAA HIKI, UNACHUKUA DHAMANA KABISA YA HATARI ZOTE ZA MATUMIZI.",
        u8"Tunashauri sana dhidi ya kutumia vipokea sauti vya masikioni kwenye kifaa chako kwa sasa. Ukichagua kupima sauti ya vipokea sauti, pimia kwa kutumia spika za nje au bila kuvaa vipokea sauti moja kwa moja kwenye masikioni mwako.",
        u8"Nakubali"
    }
}};

enum class AppState {
    Welcome,
    SetLanguage,
    HealthAndSafety
};

void drawCenteredText(const char* text) {
    float windowWidth = ImGui::GetWindowSize().x;
    float textWidth   = ImGui::CalcTextSize(text).x;
    ImGui::SetCursorPosX((windowWidth - textWidth) * 0.5f);
    ImGui::Text("%s", text);
}

void drawIconHeader(ImTextureID icon_id, const char* text, int text_y_nudge = 0) {
    ImGui::Image(icon_id, ImVec2(32, 32));
    ImGui::SameLine();
    ImGui::SetCursorPosY(ImGui::GetStyle().WindowPadding.y + 2.0f + text_y_nudge);
    ImGui::Text(text);
    //ImGui::Dummy(ImVec2(0.0f, 4.0f));
}

int main(int argc, char* argv[]) {
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMECONTROLLER) != 0) {
        return -1;
    }

    IMG_Init(IMG_INIT_PNG | IMG_INIT_JPG);

    SDL_Window* window = SDL_CreateWindow("goodluckOS Setup", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 640, 480, 0);
    SDL_SetWindowResizable(window, SDL_FALSE);

    SDL_Renderer* renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_PRESENTVSYNC | SDL_RENDERER_ACCELERATED);

    const char* iconDir = "/usr/share/icons/";
    // Load icons
    SDL_Texture* translate_icon_texture = IMG_LoadTexture(renderer, (std::string(iconDir) + "translate.png").c_str());
    ImTextureID translate_icon_id = (ImTextureID)(intptr_t)translate_icon_texture;

    SDL_Texture* headphone_warning_icon_texture = IMG_LoadTexture(renderer, (std::string(iconDir) + "headphone-warning.png").c_str());
    ImTextureID headphone_warning_icon_id = (ImTextureID)(intptr_t)headphone_warning_icon_texture;

    SDL_Texture* glos_logo_icon_texture = IMG_LoadTexture(renderer, (std::string(iconDir) +  "glos-logo-sm.png").c_str());
    ImTextureID glos_logo_icon_id = (ImTextureID)(intptr_t)glos_logo_icon_texture;

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO(); (void)io;

    io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;

    ImFontConfig baseCfg;
    const char* fontDir = "/usr/share/fonts/";
    io.Fonts->AddFontFromFileTTF(
        (std::string(fontDir) + "NotoSans.ttf").c_str(),
        24.0f,
        &baseCfg
    );

    ImFontConfig mergeCfg;
    mergeCfg.MergeMode = true;
    io.Fonts->AddFontFromFileTTF(
        (std::string(fontDir) + "NotoSansSC.ttf").c_str(),
        24.0f,
        &mergeCfg
    );

    // static vars
    static int selected_index = 2;

    ImGui_ImplSDL2_InitForSDLRenderer(window, renderer);
    ImGui_ImplSDLRenderer2_Init(renderer);
    ImGui::GetStyle().FontScaleMain = 1.25;

    SDL_GameController* controller = nullptr;
    for (int i = 0; i < SDL_NumJoysticks(); ++i) {
        if (SDL_IsGameController(i)) {
            controller = SDL_GameControllerOpen(i);
            if (controller) break;
        }
    }

    AppState state = AppState::Welcome;
    std::string errorOutput = "";
    int exitCode = 0;

    bool running = true;
    while (running) {
        SDL_Event event;

        if (SDL_WaitEvent(&event)) {
            do {
                ImGui_ImplSDL2_ProcessEvent(&event);
                if (event.type == SDL_QUIT) {
                    running = false;
                }
            } while (SDL_PollEvent(&event));
        }

        ImGui_ImplSDLRenderer2_NewFrame();
        ImGui_ImplSDL2_NewFrame();
        ImGui::NewFrame();

        ImGui::SetNextWindowPos(ImVec2(0, 0));
        ImGui::SetNextWindowSize(io.DisplaySize);
        ImGuiWindowFlags window_flags = ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoSavedSettings;

        ImGui::Begin("goodluckOS Setup", nullptr, window_flags);
        ImVec2 windowSize = ImGui::GetWindowSize();
        if (state == AppState::Welcome) {
            ImGui::Dummy(ImVec2(0.0f, 36.0f));
            const int logo_size = 64;
            ImGui::SetCursorPosX(ImGui::GetWindowSize().x / 2.0f - (logo_size / 2.0f));
            ImGui::Image(glos_logo_icon_id, ImVec2(logo_size, logo_size));
            ImGui::Dummy(ImVec2(0.0f, 6.0f));
            drawCenteredText(u8"Welcome / Bem-vindo / 欢迎 / Bienvenida");
            drawCenteredText(u8"स्वागत / Bienvenue / Добро пожаловать");
            //set cursor position to window height - button height
            ImGui::SetCursorPosY(ImGui::GetWindowSize().y - ImGui::GetStyle().WindowPadding.y - buttonHeight);
            if (ImGui::Button(languages[selected_index].continue_text.c_str(), ImVec2(-FLT_MIN, buttonHeight))) {
                state = AppState::SetLanguage;
            }
        }
        else if (state == AppState::SetLanguage) {
            drawIconHeader(translate_icon_id, u8"Select your language");

            ImGui::Dummy(ImVec2(0.0f, 64.0f));

            ImGui::SetCursorPosX(ImGui::GetStyle().WindowPadding.x + 96.0f);
            if (ImGui::BeginCombo("##language combo", languages[selected_index].name.c_str())) {
                for (int i = 0; i < languages.size(); i++) {
                    const bool is_selected = (selected_index == i);
                    if (ImGui::Selectable(languages[i].name.c_str(), is_selected)) {
                        selected_index = i;
                    }
                    if (is_selected) {
                        ImGui::SetItemDefaultFocus();
                    }
                }
                ImGui::EndCombo();
            }
            ImGui::SetCursorPosY(ImGui::GetWindowSize().y - ImGui::GetStyle().WindowPadding.y - buttonHeight);
            if (ImGui::Button(languages[selected_index].back_text.c_str(), ImVec2(ImGui::GetWindowSize().x / 2.0f, buttonHeight))) {
                state = AppState::Welcome;
            }
            ImGui::SameLine();
            if (ImGui::Button(languages[selected_index].continue_text.c_str(), ImVec2(-FLT_MIN, buttonHeight))) {
                state = AppState::HealthAndSafety;
            }
        }
        else if (state == AppState::HealthAndSafety) {
            drawIconHeader(headphone_warning_icon_id, headphone_warning_text[selected_index].title.c_str());
            //ImGui::SetWindowFontScale(1.25f);
            ImGui::TextWrapped(headphone_warning_text[selected_index].line_1.c_str());
            ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 0.5f, 0.5f, 1.0f));
            ImGui::TextWrapped(headphone_warning_text[selected_index].line_2.c_str());
            ImGui::PopStyleColor();
            ImGui::TextWrapped(headphone_warning_text[selected_index].line_3.c_str());
            //ImGui::SetWindowFontScale(1.0f);

            ImGui::SetCursorPosY(ImGui::GetWindowSize().y - ImGui::GetStyle().WindowPadding.y - buttonHeight);
            if (ImGui::Button(languages[selected_index].back_text.c_str(), ImVec2(ImGui::GetWindowSize().x / 2.0f, buttonHeight))) {
                state = AppState::SetLanguage;
            }
            ImGui::SameLine();
            if (ImGui::Button(headphone_warning_text[selected_index].i_accept.c_str(), ImVec2(-FLT_MIN, buttonHeight))) {
                running = false;
            }
        }

        ImGui::End();

        ImGui::Render();
        SDL_SetRenderDrawColor(renderer, 45, 45, 45, 255);
        SDL_RenderClear(renderer);
        ImGui_ImplSDLRenderer2_RenderDrawData(ImGui::GetDrawData(), renderer);
        SDL_RenderPresent(renderer);
    }

    if (controller) SDL_GameControllerClose(controller);

    ImGui_ImplSDLRenderer2_Shutdown();
    ImGui_ImplSDL2_Shutdown();
    ImGui::DestroyContext();

    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();

    return 0;
}
