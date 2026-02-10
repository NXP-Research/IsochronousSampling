# Isochronous Sampling
This repository contains the code for the paper Isochronous Fixed-Weight Sampling in Hardware.

The files IsochronousSampling_X_Y are the top level entites, for cryptoscheme X and variant Y.
The supported cryptoschemes are NTRU-HPS, Streamlined NTRU Prime and Classic Mceliece.
All three come in a low-area and high-speed variant.

The folder masked/ contains the files for the masked implementations, also for the cryptoschemes NTRU-HPS, Streamlined NTRU Prime and Classic Mceliece.
The folder masked/adder/ contains the Sklansky adder, and masked/lib_v/ contain the HPC2 gadgets.

Testbenches are in the folder tb/.

# License

This project is licensed under the MIT License. An SBOM file is also provided with license and dependency information.

### Third-Party Dependencies

This repository makes use of third-party code:
* The HPC2 gadgets are from https://github.com/cassiersg/fullverif/
* The masked Sklansky adder and multiplexer are from https://github.com/AdrianMarotzke/Masked-SNTRUP
* The FIFO buffer is from https://vhdlwhiz.com/ring-buffer-fifo/ 