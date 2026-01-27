import { IError, IOptions, IResult } from './Interface';
export declare class MLKitBarcodeScanner {
    private getBarcodeFormat;
    private getBarcodeType;
    private getBarcodeFormatFlags;
    scan(userOptions: IOptions, success: (result: IResult) => unknown, failure: (error: IError) => unknown): void;
    private sendScanRequest;
}
//# sourceMappingURL=BarcodeScanner.plugin.d.ts.map