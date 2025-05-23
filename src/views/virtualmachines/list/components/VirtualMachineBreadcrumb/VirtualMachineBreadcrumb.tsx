import * as React from 'react';
import { useNavigate } from 'react-router-dom-v5-compat';

import { VirtualMachineModelRef } from '@kubevirt-ui/kubevirt-api/console';
import { useKubevirtTranslation } from '@kubevirt-utils/hooks/useKubevirtTranslation';
import { useLastNamespacePath } from '@kubevirt-utils/hooks/useLastNamespacePath';
import { Breadcrumb, BreadcrumbItem, Button, ButtonVariant } from '@patternfly/react-core';

export const VirtualMachineBreadcrumb: React.FC = React.memo(() => {
  const namespacePath = useLastNamespacePath();

  const { t } = useKubevirtTranslation();
  const navigate = useNavigate();

  return (
    <Breadcrumb>
      <BreadcrumbItem>
        <Button
          isInline
          onClick={() => navigate(`/k8s/${namespacePath}/${VirtualMachineModelRef}`)}
          variant={ButtonVariant.link}
        >
          {t('VirtualMachines')}
        </Button>
      </BreadcrumbItem>
      <BreadcrumbItem>{t('VirtualMachine details')}</BreadcrumbItem>
    </Breadcrumb>
  );
});
export default VirtualMachineBreadcrumb;
