
#include "Application.h"

int main(int, char**) {
    Application app;
    app.onInit();

    while (app.isRunning()) {
        app.onFrame();

        if (app.shouldCompute()) {
            app.onCompute();
        }
    }

    app.onFinish();
    return 0;
}