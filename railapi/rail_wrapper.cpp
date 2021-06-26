#include <cstdio>

#include "rail/sdk/rail_achievement.h"
#include "rail/sdk/rail_api.h"
#include "rail/sdk/rail_event.h"
#include "rail/sdk/rail_floating_window_define.h"
#include "rail/sdk/rail_result.h"

HMODULE librail_api;
rail::helper::Invoker *invoker = nullptr;

class RailAchievement final : public rail::IRailEvent {
    rail::RailID self{ 0 };
    rail::RailString anti_addiction;
    rail::IRailPlayerAchievement *player_achievement = nullptr;
    bool antiAddictionReceived = false;
    bool playerAchievementReceived = false;

   public:
    const char *FetchAntiAddiction() {
        if (antiAddictionReceived) {
            antiAddictionReceived = false;
            return anti_addiction.c_str();
        }
        return nullptr;
    }

    RailAchievement() {
        auto system = rail::kRailEventSystemStateChanged;
        auto received = rail::kRailEventAchievementPlayerAchievementReceived;
        auto stored = rail::kRailEventAchievementPlayerAchievementStored;
        auto notify = rail::kRailEventShowFloatingNotifyWindow;
        invoker->RailRegisterEvent(system, this);
        invoker->RailRegisterEvent(received, this);
        invoker->RailRegisterEvent(stored, this);
        invoker->RailRegisterEvent(notify, this);
        auto helper = invoker->RailFactory()->RailAchievementHelper();
        player_achievement = helper->CreatePlayerAchievement(self);
        player_achievement->AsyncRequestAchievement("");
    }
    ~RailAchievement() {
        if (player_achievement) {
            player_achievement->Release();
            player_achievement = nullptr;
        }
        auto system = rail::kRailEventSystemStateChanged;
        auto received = rail::kRailEventAchievementPlayerAchievementReceived;
        auto stored = rail::kRailEventAchievementPlayerAchievementStored;
        auto notify = rail::kRailEventShowFloatingNotifyWindow;
        invoker->RailUnregisterEvent(notify, this);
        invoker->RailUnregisterEvent(stored, this);
        invoker->RailUnregisterEvent(received, this);
        invoker->RailUnregisterEvent(system, this);
    }
    bool IsReady() const { return playerAchievementReceived; }
    bool HasAchieved(LPCSTR name_) const {
        if (!IsReady()) return false;
        bool ret = false;
        rail::RailString name{ name_ };
        player_achievement->HasAchieved(name, &ret);
        return ret;
    }
    bool Make(LPCSTR name_) const {
        if (!IsReady()) return false;
        rail::RailString name{ name_ };
        return player_achievement->MakeAchievement(name) == rail::kSuccess;
    }
    bool Make(LPCSTR name_, int cur, int max) const {
        if (!IsReady()) return false;
        rail::RailString name{ name_ };
        return player_achievement->AsyncTriggerAchievementProgress(
                   name, cur, max) == rail::kSuccess;
    }
    bool Cancel(LPCSTR name_) const {
        if (!IsReady()) return false;
        rail::RailString name{ name_ };
        return player_achievement->CancelAchievement(name) == rail::kSuccess;
    }
    bool Save() const {
        return player_achievement->AsyncStoreAchievement("") == rail::kSuccess;
    }
    void OnRailEvent(rail::RAIL_EVENT_ID event_id,
                     rail::EventBase *param) override {
        using namespace rail::rail_event;
        switch (event_id) {
            case rail::kRailEventAchievementPlayerAchievementReceived: {
                playerAchievementReceived = true;
                break;
            }
            case rail::kRailEventAchievementPlayerAchievementStored: {
                auto event = static_cast<PlayerAchievementStored *>(param);
                // TODO: callback(event->achievement_name)?
                (void) event;
                break;
            }
            case rail::kRailEventSystemStateChanged: {
                auto event = static_cast<RailSystemStateChanged *>(param);
                printf("[rail_wrapper] >>> RailSystemStateChanged: %d\n", event->state);
                if (event->state == rail::kSystemStatePlatformOffline ||
                    event->state == rail::kSystemStatePlatformExit ||
                    event->state == rail::kSystemStatePlayerOwnershipExpired ||
                    event->state == rail::kSystemStateGameExitByAntiAddiction) {
                    // exit(0);
                }
                break;
            }
            case rail::kRailEventShowFloatingNotifyWindow: {
                auto event = static_cast<ShowNotifyWindow *>(param);
                if (event->window_type == rail::kRailNotifyWindowAntiAddiction) {
                    anti_addiction = event->json_content;
                    antiAddictionReceived = true;
                }
                break;
            }
            default:
                return;
        }
    }
};

RailAchievement *railAchievement = nullptr;

const char *argv = "";
const char *debu = "--rail_debug_mode";

bool __stdcall init(LPCSTR path, int id, bool debug, bool no_anti_addiction) {
    librail_api = LoadLibrary(path);
    if (librail_api == nullptr) return false;
    invoker = new rail::helper::Invoker(librail_api);
    bool ret = false;
    if (debug)
        ret = invoker->RailNeedRestartAppForCheckingEnvironment(id, 1, &debu);
    else
        ret = invoker->RailNeedRestartAppForCheckingEnvironment(id, 1, &argv);
    if (ret) return false;
    ret = invoker->RailInitialize();
    if (!ret) return false;
    if (no_anti_addiction) {
        invoker->RailFactory()->RailFloatingWindow()->SetNotifyWindowEnable(rail::kRailNotifyWindowAntiAddiction, false);
    }
    railAchievement = new RailAchievement();
    printf("[rail_wrapper] init success! anti_addiction is %s\n", no_anti_addiction ? "OFF" : "ON");
    return ret;
}

bool __stdcall term() {
    if (invoker) {
        invoker->RailFinalize();
        delete invoker;
        invoker = nullptr;
        delete railAchievement;
        railAchievement = nullptr;
        FreeLibrary(librail_api);
        librail_api = nullptr;
    }
    return true;
}

bool __stdcall has(LPCSTR name) {
    if (!railAchievement) return false;
    return railAchievement->HasAchieved(name);
}

bool __stdcall update() {
    if (!invoker) return false;
    invoker->RailFireEvents();
    return true;
}

bool __stdcall ready() {
    if (!railAchievement) return false;
    return railAchievement->IsReady();
}

bool __stdcall make(LPCSTR name) {
    if (!railAchievement) return false;
    return railAchievement->Make(name) && railAchievement->Save();
}

bool __stdcall cancel(LPCSTR name) {
    if (!railAchievement) return false;
    return railAchievement->Cancel(name) && railAchievement->Save();
}

bool __stdcall progress(LPCSTR name, int cur, int max) {
    if (!railAchievement) return false;
    return railAchievement->Make(name, cur, max);
}

char *__stdcall anti_addiction() {
    if (!railAchievement) return nullptr;
    return (char *)railAchievement->FetchAntiAddiction();
}
