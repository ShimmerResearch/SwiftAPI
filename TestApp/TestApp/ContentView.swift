//
//  ContentView.swift
//  TestApp
//
//  Created by Shimmer Engineering on 19/10/2023.
//

import SwiftUI

struct ContentView: View {
    @StateObject var viewModel = ViewModel()
    @State private var showThroughput = false

    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
            
        }
        .padding()

        Button("Throughput Test", action: { showThroughput = true })
            .sheet(isPresented: $showThroughput) { ThroughputView() }
        Button("Scan Veri",action: { viewModel.test()})
        Button("Connect Dev1",action: { Task {
            do {
                await viewModel.connect()
            } catch {
                print("Error: \(error)")
            }
        }
        })
        Button("Disconnect Dev1",action: { Task {
            do {
                await viewModel.disconnect()
            } catch {
                print("Error: \(error)")
            }
        }
        })
        Button("Read Production Dev1",action:{
            Task {
                do {
                    await viewModel.sendReadProductionCommand()
                } catch {
                    print("Error: \(error)")
                }
            }
        })
        Button("Speed Test Dev1",action:{
            Task {
                do {
                    await viewModel.sendSpeedTestCommand()
                } catch {
                    print("Error: \(error)")
                }
            }
        })
        Button("Scan Shimmer3",action: { viewModel.scanShimmer3()})
        Button("Connect Dev2",action: {Task {
            do {
                await viewModel.connectDev2()
            } catch {
                print("Error: \(error)")
            }
        }
        })
        Button("Disconnect Dev2",action:{ Task {
            do {
                await viewModel.disconnectDev2()
            } catch {
                print("Error: \(error)")
            }
        }
        })
        Button("StartStreaming Dev2",action:{ Task {
            do {
                await viewModel.sendStartStreamingCommandDev2()
            } catch {
                print("Error: \(error)")
            }
        }
        })
        Button("StopStreaming Dev2",action:{ Task {
            do {
                await viewModel.sendStopStreamingCommandDev2()
            } catch {
                print("Error: \(error)")
            }
        }
        })
        Button("WriteInfoMem WRAccel Dev2",action:{ Task {
            do {
                await viewModel.sendInfoMemAccel()
            } catch {
                print("Error: \(error)")
            }
        }
        })
        Button("WriteInfoMem IMU Dev2",action:{ Task {
            do {
                await viewModel.sendInfoMemIMU()
            } catch {
                print("Error: \(error)")
            }
        }
        })
        Button("WriteInfoMem ECG Dev2",action:{ Task {
            do {
                await viewModel.sendInfoMemECG()
            } catch {
                print("Error: \(error)")
            }
        }
        })
        Button("WriteInfoMem EMG Dev2",action:{ Task {
            do {
                await viewModel.sendInfoMemEMG()
            } catch {
                print("Error: \(error)")
            }
        }
        })
        Button("WriteInfoMem EXG Test Dev2",action:{ Task {
            do {
                await viewModel.sendInfoMemEXGTest()
            } catch   {
                print("Error: \(error)")
            }
        }
        })
        Button("WriteInfoMem Respiration Dev2",action:{ Task {
            do {
                await viewModel.sendInfoMemRespiration()
            } catch {
                print("Error: \(error)")
            }
        }
        })
    }
}

#Preview {
    ContentView()
}
