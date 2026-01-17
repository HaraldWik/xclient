#include <sys/socket.h>
#include <sys/un.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>


int32_t GlobalId = 0;
int32_t GlobalIdBase = 0;
int32_t GlobalIdMask = 0;
int32_t GlobalRootWindow = 0;
int32_t GlobalRootVisualId = 0;

#define READ_BUFFER_SIZE 16*1024

#define RESPONSE_STATE_FAILED 0
#define RESPONSE_STATE_SUCCESS 1
#define RESPONSE_STATE_AUTHENTICATE 2

#define X11_REQUEST_CREATE_WINDOW 1
#define X11_REQUEST_MAP_WINDOW 8
#define X11_REQUEST_IMAGE_TEXT_8 76
#define X11_REQUEST_OPEN_FONT 45
#define X11_REQUEST_CREATE_GC 55


#define X11_EVENT_FLAG_KEY_PRESS 0x00000001
#define X11_EVENT_FLAG_KEY_RELEASE 0x00000002
#define X11_EVENT_FLAG_EXPOSURE 0x8000

#define PAD(N) ((4 - (N % 4)) % 4)

void VerifyOrDie(int IsSuccess, const char *Message) {
    if(!IsSuccess)  {
        fprintf(stderr, "%s", Message);
        exit(13);
    }
}

void VerifyOrDieWidthErrno(int IsSuccess, const char *Message) {
    if(!IsSuccess)  {
        perror(Message);
        exit(13);
    }
}

void DumpResponseError(int Socket, char* ReadBuffer) {
        uint8_t ReasonLength = ReadBuffer[1];
        uint16_t MajorVersion = *((uint16_t*)&ReadBuffer[2]);
        uint16_t MinorVersion = *((uint16_t*)&ReadBuffer[4]);
        uint16_t AdditionalDataLength = *((uint16_t*)&ReadBuffer[6]); // Length in 4-byte units of "additional data"
        uint8_t *Message = (uint8_t*)&ReadBuffer[8];

        int BytesRead = read(Socket, ReadBuffer + 8, READ_BUFFER_SIZE-8);

        printf("State: %d\n", ReadBuffer[0]);
        printf("MajorVersion: %d\n", MajorVersion);
        printf("MinorVersion: %d\n", MinorVersion);
        printf("AdditionalDataLength: %d\n", AdditionalDataLength);
        printf("Reason: %s\n", Message);
}

void AuthenticateX11() {
    fprintf(stderr, "Current version of the app does not support authentication.\n");
    fprintf(stderr, "Please run 'xhost +local:' in your terminal to disable cookie based authentication\n");
    fprintf(stderr, "and allow local apps to communication with Xorg without it.");
}

int32_t GetNextId() {
    int32_t Result = (GlobalIdMask & GlobalId) | GlobalIdBase;
    GlobalId += 1;
    return Result;
}

void PrintResponseError(char *Data, int32_t Size) {
    char ErrorCode = Data[1];
    printf("\033[0;31m");
    printf("Response Error: [%d]", ErrorCode);
    printf("\033[0m\n");
}

void PrintAndProcessEvent(char *Data, int32_t Size) {
    char EventCode = Data[0];
    printf("Some event occured: %d\n", EventCode);

}

void GetAndProcessReply(int Socket) {
    char Buffer[1024] = {};
    int32_t BytesRead = read(Socket, Buffer, 1024);

    uint8_t Code = Buffer[0];

    if(Code == 0) {
        PrintResponseError(Buffer, BytesRead);
    } else if (Code == 1) {
        printf("---------------- Unexpected reply\n");
    } else {
        // NOTE: Event?
        PrintAndProcessEvent(Buffer, BytesRead);
    }
}

int main(){
    int Socket = socket(AF_UNIX, SOCK_STREAM, 0);
    VerifyOrDie(Socket > 0, "Couldn't open a socket(...)");

    struct sockaddr_un Address;
    memset(&Address, 0, sizeof(struct sockaddr_un));
    Address.sun_family = AF_UNIX;
    strncpy(Address.sun_path, "/tmp/.X11-unix/X0", sizeof(Address.sun_path)-1);

    int Status = connect(Socket, (struct sockaddr *)&Address, sizeof(Address));
    VerifyOrDieWidthErrno(Status == 0, "Couldn't connect to a unix socket with connect(...)");

    char SendBuffer[16*1024] = {};
    char ReadBuffer[16*1024] = {};

    uint8_t InitializationRequest[12] = {};
    InitializationRequest[0] = 'l';
    InitializationRequest[1] = 0;
    InitializationRequest[2] = 11;

    int BytesWritten = write(Socket, (char*)&InitializationRequest, sizeof(InitializationRequest));
    VerifyOrDie(BytesWritten == sizeof(InitializationRequest), "Wrong amount of bytes written during initialization");

    int BytesRead = read(Socket, ReadBuffer, 8);

    if(ReadBuffer[0] == RESPONSE_STATE_FAILED) {
        DumpResponseError(Socket, ReadBuffer);
    }
    else if(ReadBuffer[0] == RESPONSE_STATE_AUTHENTICATE) {
        AuthenticateX11();
    }
    else if(ReadBuffer[0] == RESPONSE_STATE_SUCCESS) {
        printf("INIT Response SUCCESS. BytesRead: %d\n", BytesRead);

        BytesRead = read(Socket, ReadBuffer + 8, READ_BUFFER_SIZE-8);
        printf("---------------------------%d\n", BytesRead);

        /* -------------------------------------------------------------------------------- */
        uint8_t _Unused = ReadBuffer[1];
        uint16_t MajorVersion = *((uint16_t*)&ReadBuffer[2]);
        uint16_t MinorVersion = *((uint16_t*)&ReadBuffer[4]);
        uint16_t AdditionalDataLength = *((uint16_t*)&ReadBuffer[6]); // Length in 4-byte units of "additional data"

        uint32_t ResourceIdBase = *((uint32_t*)&ReadBuffer[12]);
        uint32_t ResourceIdMask = *((uint32_t*)&ReadBuffer[16]);
        uint16_t LengthOfVendor = *((uint16_t*)&ReadBuffer[24]);
        uint8_t NumberOfFormants = *((uint16_t*)&ReadBuffer[29]);
        uint8_t *Vendor = (uint8_t *)&ReadBuffer[40];

        int32_t VendorPad = PAD(LengthOfVendor);
        int32_t FormatByteLength = 8 * NumberOfFormants;
        int32_t ScreensStartOffset = 40 + LengthOfVendor + VendorPad + FormatByteLength;

        uint32_t RootWindow = *((uint32_t*)&ReadBuffer[ScreensStartOffset]);
        uint32_t RootVisualId = *((uint32_t*)&ReadBuffer[ScreensStartOffset + 32]);

        GlobalIdBase = ResourceIdBase;
        GlobalIdMask = ResourceIdMask;
        GlobalRootWindow = RootWindow;
        GlobalRootVisualId = RootVisualId;

        printf("Base: %d\n", ResourceIdBase);
        printf("IdMask: %d\n", ResourceIdMask);
        printf("LengthOfVendor: %d\n", LengthOfVendor);

        /* -------------------------------------------------------------------------------- */
        // ------------------------------ Create Window
        int32_t WindowId = GetNextId();
        int32_t Depth = 0;
        int32_t X = 100;
        int32_t Y = 100;
        uint32_t Width = 600;
        uint32_t Height = 300;
        uint32_t BorderWidth = 1;
        int32_t CreateWindowFlagCount = 2;
        int RequestLength = 8+CreateWindowFlagCount;


#define WINDOWCLASS_COPYFROMPARENT 0
#define WINDOWCLASS_INPUTOUTPUT 1
#define WINDOWCLASS_INPUTONLY 2

#define X11_FLAG_BACKGROUND_PIXEL 0x00000002 
#define X11_FLAG_WIN_EVENT 0x00000800 

        SendBuffer[0] = X11_REQUEST_CREATE_WINDOW;
        SendBuffer[1] = Depth;
        *((int16_t *)&SendBuffer[2]) = RequestLength;
        *((int32_t *)&SendBuffer[4]) = WindowId;
        *((int32_t *)&SendBuffer[8]) = GlobalRootWindow;
        *((int16_t *)&SendBuffer[12]) = X;
        *((int16_t *)&SendBuffer[14]) = Y;
        *((int16_t *)&SendBuffer[16]) = Width;
        *((int16_t *)&SendBuffer[18]) = Height;
        *((int16_t *)&SendBuffer[20]) = BorderWidth;
        *((int16_t *)&SendBuffer[22]) = WINDOWCLASS_INPUTOUTPUT;
        *((int32_t *)&SendBuffer[24]) = GlobalRootVisualId;
        *((int32_t *)&SendBuffer[28]) = X11_FLAG_WIN_EVENT | X11_FLAG_BACKGROUND_PIXEL;
        *((int32_t *)&SendBuffer[32]) = 0xff000000;
        *((int32_t *)&SendBuffer[36]) = X11_EVENT_FLAG_EXPOSURE | X11_EVENT_FLAG_KEY_PRESS;


        BytesWritten = write(Socket, (char *)&SendBuffer, RequestLength*4);
        printf("Create Window: BytesWritten: %d\n", BytesWritten);


        // ------------------------------ Map Window

        SendBuffer[0] = X11_REQUEST_MAP_WINDOW;
        SendBuffer[1] = 0;
        *((int16_t *)&SendBuffer[2]) = 2;
        *((int32_t *)&SendBuffer[4]) = WindowId;

        BytesWritten = write(Socket, (char *)&SendBuffer, 2*4);
        printf("Map Window: BytesWritten: %d\n", BytesWritten);


        /* ------------------------------------------------------------------------------- */

        struct pollfd PollDescriptors[1] = {};
        PollDescriptors[0].fd = Socket;
        PollDescriptors[0].events = POLLIN;
        int32_t DescriptorCount = 1;

        int32_t IsProgramRunning = 1;
        while(IsProgramRunning){
            int32_t EventCount = poll(PollDescriptors, DescriptorCount, -1);

            if(PollDescriptors[0].revents & POLLERR) {
                printf("------- Error\n");
            }

            if(PollDescriptors[0].revents & POLLHUP) {
                printf("---- Connection close\n");
                IsProgramRunning = 0;
            }

            GetAndProcessReply(PollDescriptors[0].fd);
        }
    }

}