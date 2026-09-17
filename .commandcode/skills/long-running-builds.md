# Long-Running Builds Policy

- Just run the build tool and stop there; there is no need to monitor the process synchronously.
- For builds/CI-style jobs, launch the documented command once, report that it started, and do not tail logs, poll for completion, or babysit.
- The user acts as the error reporter. Let the user know if any errors arise instead of waiting and watching it.
- Verification of *correctness* is wanted eventually, but synchronous monitoring of *progress* is not. Launch the script in the background and move on, or inform the user it was launched.