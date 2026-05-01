
#include "Application.h"

int main(int, char**) {
    Application app;
    app.onInit();

    while (app.isRunning()) {
        app.onCompute();
        app.onFrame();
    }

    app.onFinish();
    return 0;
}
