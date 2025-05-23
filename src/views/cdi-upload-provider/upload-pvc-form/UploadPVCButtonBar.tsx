import React, { ReactNode } from 'react';

import Loading from '@kubevirt-utils/components/Loading/Loading';
import { Alert, AlertGroup, AlertVariant } from '@patternfly/react-core';

import { injectDisabled } from '../utils/utils';

import UploadErrorMessage from './UploadPVCErrorMessage';

type UploadPVCButtonBarProps = {
  children?: ReactNode;
  className?: string;
  errorMessage?: string;
  infoMessage?: string;
  inProgress?: boolean;
  successMessage?: string;
  uploadProxyURL?: string;
};

const UploadPVCButtonBar: React.FC<UploadPVCButtonBarProps> = ({
  children,
  className,
  errorMessage,
  infoMessage,
  inProgress,
  successMessage,
  uploadProxyURL,
}) => {
  return (
    <div className={className}>
      <AlertGroup
        aria-atomic="false"
        aria-live="polite"
        aria-relevant="additions text"
        isLiveRegion
      >
        {successMessage && <Alert isInline title={successMessage} variant={AlertVariant.success} />}
        {errorMessage && (
          <UploadErrorMessage message={errorMessage} uploadProxyURL={uploadProxyURL} />
        )}
        {injectDisabled(children, inProgress)}
        {inProgress && <Loading />}
        {infoMessage && <Alert isInline title={infoMessage} variant={AlertVariant.info} />}
      </AlertGroup>
    </div>
  );
};

export default UploadPVCButtonBar;
